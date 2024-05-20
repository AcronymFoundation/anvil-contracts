// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./AnvilVotes.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice This is an exact clone of OpenZeppelin's {ERC20Votes} contract with the following modifications:
 *   - _getVotingUnits(...) is removed, as it is no longer required by the parent contract.
 *   - _maxSupply(...) is declared abstract, in favor of implementation in Anvil.sol.
 *   - _transferVotingUnits(...) is declared as abstract in this file (it originally was in Votes.sol, but it is no longer necessary there.)
 */
abstract contract AnvilERC20Votes is ERC20, AnvilVotes {
    /**
     * @dev Total supply cap has been exceeded, introducing a risk of votes overflowing.
     */
    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);

    //    NB: This is abstract and implemented in Anvil.sol instead for clarity.
    //    /**
    //     * @dev Maximum token supply. Defaults to `type(uint208).max` (2^208^ - 1).
    //     *
    //     * This maximum is enforced in {_update}. It limits the total supply of the token, which is otherwise a uint256,
    //     * so that checkpoints can be stored in the Trace208 structure used by {{Votes}}. Increasing this value will not
    //     * remove the underlying limitation, and will cause {_update} to fail because of a math overflow in
    //     * {_transferVotingUnits}. An override could be used to further restrict the total supply (to a lower value) if
    //     * additional logic requires it. When resolving override conflicts on this function, the minimum should be
    //     * returned.
    //     */
    //    function _maxSupply() internal view virtual returns (uint256) {
    //        return type(uint208).max;
    //    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
        if (from == address(0)) {
            uint256 supply = totalSupply();
            uint256 cap = _maxSupply();
            if (supply > cap) {
                revert ERC20ExceededSafeSupply(supply, cap);
            }
        }
        _transferVotingUnits(from, to, value);
    }

    //    NB: This is no longer necessary, as vote delegation logic is in Anvil.sol.
    //    /**
    //     * @dev Returns the voting units of an `account`.
    //     *
    //     * WARNING: Overriding this function may compromise the internal vote accounting.
    //     * `ERC20Votes` assumes tokens map to voting units 1:1 and this is not easy to change.
    //     */
    //    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
    //        return balanceOf(account);
    //    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account) public view virtual returns (uint32) {
        return _numCheckpoints(account);
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _checkpoints(account, pos);
    }

    /*************
     * ADDITIONS *
     *************/

    // NB: this is referenced in this file and must be implemented in Anvil.sol, where delegation logic lives.
    /**
     * @dev Must transfer voting units as a result of the transfer of `value` tokens from `from` to `to`.
     */
    function _transferVotingUnits(address from, address to, uint256 value) internal virtual;

    // NB: This had existed in this file (see above) but is now abstract instead for clarity.
    /**
     * @dev Maximum token supply.
     *
     * This maximum is enforced in {_update}. It limits the total supply of the token, which is otherwise a uint256,
     * so that checkpoints can be stored in the Trace208 structure used by {{Votes}}. Increasing this value will not
     * remove the underlying limitation, and will cause {_update} to fail because of a math overflow in
     * {_transferVotingUnits}. An override could be used to further restrict the total supply (to a lower value) if
     * additional logic requires it. When resolving override conflicts on this function, the minimum should be
     * returned.
     */
    function _maxSupply() internal view virtual returns (uint256);
}
