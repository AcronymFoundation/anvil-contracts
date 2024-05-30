// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "./IClaimable.sol";
import "./AnvilERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title Anvil Token
 * @notice Anvil governance token, using OZ ERC20Votes but adding the ability to delegate votes locked in Claim.sol.
 *
 * @dev Anvil depends on the referenced `IClaimable` contract, allowing tokens that are locked within that contract but
 * belong, or will belong after vesting, to a specific address to be delegated for governance purposes.
 *
 * Note: The ERC20Votes / Votes contract logic needed to be copied rather than extended because there are a number of
 * functions and members that need to be accessed or overridden but cannot be because they are private.
 */
contract Anvil is AnvilERC20Votes {
    using Checkpoints for Checkpoints.Trace208;

    error CannotDelegateToClaimContract();

    /// The contract that contains token allocations for various addresses that may be delegated.
    IClaimable public immutable claimContract;

    /// @notice A cache of the proven unclaimed amount for each account, IFF proof has occurred. This will be 0 if the
    /// account has not proven their claimable balance, which will also be true if there is no balance for it to prove.
    /// This is set in proveAndDelegate(...) and updated in the claim logic of _moveVotingPower(...).
    mapping(address => uint256) public accountProvenUnclaimedAmount;

    /**
     * @notice Deploys the Anvil token, allocating the provided amount of tokens to the provided claim contract, sending
     * the rest to the deploying address.
     * @param _claimContract The claim contract used for initial token issuance.
     * @param _claimContractBalance The amount that should be sent to the claim contract in the constructor.
     */
    constructor(IClaimable _claimContract, uint256 _claimContractBalance) ERC20("Anvil", "ANVL") EIP712("Anvil", "1") {
        claimContract = _claimContract;

        // Total supply 100 Billion + decimals.
        // TODO: Update this when we know balances.
        // Lock some tokens in claim contract.
        _mint(address(_claimContract), _claimContractBalance);
        // Send some tokens to msg.sender to allocate outside of claim contract.
        _mint(msg.sender, _maxSupply() - _claimContractBalance);
    }

    /****************
     * UNIQUE LOGIC *
     ****************/

    /**
     * @notice Proves the provided initial balance for the sender in the Claimable contract and delegates votes from
     * `msg.sender` to the `_to` address.
     *
     * Note: `delegate(...)` should be used in place of this function after initial proof or if the account in question
     * does not have a provable balance, but there is no harm other than gas cost in calling this multiple times.
     * @param _to The address to delegate votes to.
     * @param _initialBalance The initial balance for the sender that is being proven in the Claimable contract.
     * @param _proof The merkle proof for the sender that is used to prove in the Claimable contract.
     */
    function proveAndDelegate(address _to, uint256 _initialBalance, bytes32[] calldata _proof) public {
        uint256 newlyProvenAmount = claimContract.proveInitialBalance(msg.sender, _initialBalance, _proof);
        if (newlyProvenAmount > 0) {
            // NB: The call to `proveInitialBalance(...)` proved `_initialBalance` is allocated to `msg.sender` in `claimContract`.
            accountProvenUnclaimedAmount[msg.sender] = _initialBalance;
            _delegateIncludingClaimBalance(msg.sender, _to, true);
        } else {
            // NB: if we're in this branch, we have no assurance `_initialBalance` is allocated to `msg.sender` in `claimContract`.
            // It may or may not be correct - in either case the proof was a no-op.
            _delegateIncludingClaimBalance(msg.sender, _to, false);
        }
    }

    /***************
     * VOTES LOGIC *
     ***************/
    // NB: From a pure OOP standpoint, these functions should be in AnvilVotes.sol or AnvilERC20Votes.sol.
    // They are in this file because but we wanted to keep the others as close to OZ's contracts as possible with
    // significant modifications called out by being in a separate file.

    /**
     * @inheritdoc AnvilERC20Votes
     *
     * @dev Overridden to handle claim contract voting power.
     */
    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual override {
        address claimContractAddress = address(claimContract);

        if (from == claimContractAddress) {
            uint256 provenUnclaimed = accountProvenUnclaimedAmount[to];
            if (provenUnclaimed > 0) {
                // A claim is happening -- no voting power will be updated.
                // NB: Claim contract rescue destination should not have a claimable balance so this should never be entered for token rescue.
                // If it does, rescue will be treated as a claim until there is no unclaimed amount left, possibly causing this line to underflow.
                accountProvenUnclaimedAmount[to] = provenUnclaimed - amount;
            } else {
                // A rescue is happening -- voting power of the `delegates[to]` account will be increased by `amount`.
                _moveVotingPower(to, claimContractAddress, delegates(to), amount, true, false);
            }
        } else {
            // A regular transfer is happening.
            _moveVotingPower(from, delegates(from), delegates(to), amount, true, false);
        }
    }

    /**
     * @inheritdoc AnvilVotes
     *
     * @dev Overridden to handle claim contract voting power.
     */
    function _delegate(address account, address delegatee) internal virtual override {
        _delegateIncludingClaimBalance(account, delegatee, false);
    }

    /**
     * @dev Delegates voting units from account to delegatee, accounting for any claim contract delegable units.
     * @param _account The account whose voting units will be delegated.
     * @param _to The account to which voting units will be delegated.
     * @param _hasNewProvenAmount True if _account has a new proven balance this call that it previously did not have.
     */
    function _delegateIncludingClaimBalance(address _account, address _to, bool _hasNewProvenAmount) internal {
        if (_to == address(claimContract)) revert CannotDelegateToClaimContract();

        uint256 delegatorBalance = balanceOf(_account);

        address from = delegates(_account);
        _delegatee[_account] = _to;

        emit DelegateChanged(_account, from, _to);

        _moveVotingPower(_account, from, _to, delegatorBalance, false, _hasNewProvenAmount);
    }

    /**
     * @dev Moves the provided _amount of _delegator voting power from the _from address to the _to address.
     * @param _delegator The account to which voting power belongs (but is being delegated).
     * @param _from The account from which voting power is being transferred.
     * @param _to The account to which voting power is being transferred.
     * @param _tokenAmount The token amount being transferred. Note: voting power may be more than this due to Claim contract balances.
     * @param _isTransfer True if this is being called as a result of a transfer operation.
     * @param _delegatorHasNewProvenAmount True if this is being called as a result of a new balance being proven for
     * the _delegator in the Claim contract.
     */
    function _moveVotingPower(
        address _delegator,
        address _from,
        address _to,
        uint256 _tokenAmount,
        bool _isTransfer,
        bool _delegatorHasNewProvenAmount
    ) internal {
        uint256 fromVotingUnitDelta;
        uint256 toVotingUnitDelta;
        if (_isTransfer) {
            // NB: claims should not call this function, as no delegates are updated as a part of claim.
            // We can assume this is a Claim contract rescue or regular transfer. In each case, only the tokens move.
            toVotingUnitDelta = _tokenAmount;
            fromVotingUnitDelta = _tokenAmount;
        } else {
            uint256 delegatorProvenUnclaimedUnits = accountProvenUnclaimedAmount[_delegator];

            // This is a delegation action.
            if (_from == _to) {
                // This is a proveAndDelegate(...) with new tokens. _to already has token voting units; just add proven.
                toVotingUnitDelta = _delegatorHasNewProvenAmount ? delegatorProvenUnclaimedUnits : 0;
            } else {
                toVotingUnitDelta = _tokenAmount + delegatorProvenUnclaimedUnits;
                // If _hasNewProvenAmount, _from doesn't have those voting units, so do not subtract.
                fromVotingUnitDelta = _delegatorHasNewProvenAmount
                    ? _tokenAmount
                    : delegatorProvenUnclaimedUnits + _tokenAmount;
            }
        }

        address claimContractAddress = address(claimContract);
        if (_from != address(0) && fromVotingUnitDelta != 0 && _from != claimContractAddress) {
            (uint256 oldValue, uint256 newValue) = _push(
                _delegateCheckpoints[_from],
                _subtract,
                SafeCast.toUint208(fromVotingUnitDelta)
            );
            emit DelegateVotesChanged(_from, oldValue, newValue);
        }

        if (_to != address(0) && toVotingUnitDelta != 0 && _to != claimContractAddress) {
            (uint256 oldValue, uint256 newValue) = _push(
                _delegateCheckpoints[_to],
                _add,
                SafeCast.toUint208(toVotingUnitDelta)
            );
            emit DelegateVotesChanged(_to, oldValue, newValue);
        }
    }

    /*****************************
     * EXACT COPY FROM Votes.sol *
     *****************************/

    function _push(
        Checkpoints.Trace208 storage store,
        function(uint208, uint208) view returns (uint208) op,
        uint208 delta
    ) private returns (uint208, uint208) {
        return store.push(clock(), op(store.latest(), delta));
    }

    function _add(uint208 a, uint208 b) private pure returns (uint208) {
        return a + b;
    }

    function _subtract(uint208 a, uint208 b) private pure returns (uint208) {
        return a - b;
    }
}
