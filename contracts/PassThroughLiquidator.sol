// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "../interfaces/ILiquidator.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice ILiquidator implementation that liquidates by determining the contract to call as well as
 * the data to call it with from calldata. This is meant to be generic, allowing liquidation logic
 * to change without redeploying.
 * @dev This contract is UUPS-upgradeable so that its address may remain stable across logic changes.
 */
contract PassThroughLiquidator is ILiquidator, Ownable2StepUpgradeable, UUPSUpgradeable {
  using SafeERC20 for IERC20;

  address private authorizedCaller;

  error Unauthorized();
  error InvalidZeroAddress();
  error InsufficientOutputTokenReceived(uint256 expected, uint256 received);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes this contract, setting the owner and authorized caller.
   * @param _owner The address to set as the owner of this contract.
   * @param _authorizedCaller The only address permitted to call liquidate(...).
   */
  function initialize(address _owner, address _authorizedCaller) external initializer {
    if (_authorizedCaller == address(0)) revert InvalidZeroAddress();

    __Ownable_init(_owner);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    authorizedCaller = _authorizedCaller;
  }

  /**
   * Encodes the provided data so that it may be passed as the last argument of liquidate(...).
   * @param _addressToApprove The address that will be ERC-20 approved to transfer assets being liquidated.
   * @param _targetContract The contract to be called with `_data` to accomplish the liquidation.
   * @param _data The data being passed to `_targetContract` to accomplish the liquidation.
   * @return The encoded bytes.
   */
  function encodeParameters(
    address _addressToApprove,
    address _targetContract,
    bytes memory _data
  ) external pure returns (bytes memory) {
    return abi.encode(_addressToApprove, _targetContract, _data);
  }

  /**
   * Liquidates via the contract and data provided in the last parameter (`_liquidationParams`).
   * The liquidation path executed on the target contract must send the resulting output tokens to
   * THIS contract. After the target call, this contract verifies that at least `_outputTokenAmount`
   * of the output token was received, sends exactly `_outputTokenAmount` to the caller, and retains
   * any excess (recoverable by the owner via `retrieveTokens(...)`). Any input tokens that were not
   * consumed by the liquidation path are refunded to `_initiator`.
   * @dev Note: _liquidatorParams must be encoded in the format outlined by `encodeParameters(...)` above.
   *
   * @inheritdoc ILiquidator
   */
  function liquidate(
    address _initiator,
    address _inputTokenAddress,
    uint256 _maxInputTokenAmount,
    address _outputTokenAddress,
    uint256 _outputTokenAmount,
    bytes calldata // _liquidatorParams
  ) external {
    if (msg.sender != authorizedCaller) revert Unauthorized();

    IERC20 inputToken = IERC20(_inputTokenAddress);
    uint256 inputTokenBalanceBefore = inputToken.balanceOf(address(this));

    address addressToApprove;
    {
      // The next two calls may return `false` on failure. Instead of asserting `true`, we'll save gas in the
      // happy path at the expense of gas in the failure path, which will revert in the swap below.

      /*** Obtain collateral tokens from msg.sender ***/
      // NB: This will fail without sufficient allowance provided by msg.sender
      inputToken.safeTransferFrom(msg.sender, address(this), _maxInputTokenAmount);

      assembly ("memory-safe") {
        // Calldata words 0-5 (ignoring method ID) are the parameters
        // [skipped] word 6 is the length of the _liquidatorParams bytes, but we know the structure of it so we can ignore it
        // word 7: 7*32 + 4 for method ID = 228 — this is the addressToApprove
        addressToApprove := calldataload(228)
      }

      inputToken.forceApprove(addressToApprove, _maxInputTokenAmount);
    }

    uint256 outputTokenBalanceBefore = IERC20(_outputTokenAddress).balanceOf(address(this));

    assembly ("memory-safe") {
      // word 8: 8*32 + 4 = 260 for method ID — this is the targetContract
      let targetContract := calldataload(260)
      // [skipped] word 9 of calldata is the byte index in the _liquidationParams where the encoded "data" starts (we know that is 96)

      // Set targetCalldata equal to the free memory pointer location. NB: we are not "allocating" memory.
      // We're just using unallocated memory as scratch space since we know that nothing will overwrite it while we use it.
      let targetCalldata := mload(0x40)
      // word 10: 10*32 + 4 for method ID = 324 — this is the size of the "data" array from _liquidatorParams
      let targetCalldataSize := calldataload(324)
      // word 11: 11*32 + 4 for method ID = 356 — this is the start byte of the bytes that make up "data"
      calldatacopy(targetCalldata, 356, targetCalldataSize) // populate data for the call below

      // call the targetContract with the provided data to execute the liquidation.
      let ok := call(gas(), targetContract, 0, targetCalldata, targetCalldataSize, 0, 0)
      if iszero(ok) {
        // NB: Just reuse the targetCalldata pointer since it's done being used.
        returndatacopy(targetCalldata, 0, returndatasize())
        revert(targetCalldata, returndatasize())
      }
    }

    // The target has finished pulling this call's input. Revoke any remainder before this contract
    // retains excess output or receives future balances that the target must not be able to spend.
    inputToken.forceApprove(addressToApprove, 0);

    /*** Verify sufficient output tokens were received and forward the exact amount to the caller ***/
    uint256 receivedAmount = IERC20(_outputTokenAddress).balanceOf(address(this)) - outputTokenBalanceBefore;
    if (receivedAmount < _outputTokenAmount) revert InsufficientOutputTokenReceived(_outputTokenAmount, receivedAmount);

    // NB: Any excess output tokens received remain in this contract and may be swept by the owner
    // via retrieveTokens(...).
    IERC20(_outputTokenAddress).safeTransfer(msg.sender, _outputTokenAmount);

    /*** Refund input tokens that were not consumed by the liquidation path to the initiator ***/
    // NB: This mirrors the (now deprecated) UniswapLiquidator behavior of not retaining unused input tokens.
    uint256 unusedInputTokenAmount = inputToken.balanceOf(address(this)) - inputTokenBalanceBefore;
    if (unusedInputTokenAmount > 0) {
      inputToken.safeTransfer(_initiator, unusedInputTokenAmount);
    }
  }

  /**
   * @notice Transfers the entire balance of the specified token to the owner.
   * @dev Note that only the owner address may call this function.
   * @param _tokens The tokens to transfer to the owner.
   */
  function retrieveTokens(IERC20[] calldata _tokens) external onlyOwner {
    for (uint256 i = 0; i < _tokens.length; ++i) {
      uint256 balance = IERC20(_tokens[i]).balanceOf(address(this));
      if (balance > 0) {
        IERC20(_tokens[i]).safeTransfer(owner(), balance);
      }
    }
  }

  /**
   * @notice Authorizes upgrades of this contract's implementation.
   * @dev Note that only the owner address may upgrade.
   */
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
