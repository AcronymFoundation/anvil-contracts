// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./interfaces/ICollateral.sol";
import "./interfaces/ILiquidator.sol";
import "./interfaces/ILiquidatable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./Refundable.sol";
import "./interfaces/ILetterOfCredit.sol";

/**
 * @title Contract for the creation, management, and redemption of collateralized Letters of Credit (LOCs) between parties.
 */
contract LetterOfCredit is ILetterOfCredit, ILiquidatable, Ownable2Step, ReentrancyGuard, Refundable {
    using SafeERC20 for IERC20;

    /******************
     * CONTRACT STATE *
     ******************/

    /// NB: uint96 stores up to 7.9 x 10^28 and packs tightly with addresses (12 + 20 = 32 bytes).
    uint96 public locNonce;

    /// Max age of oracle update.
    /// NB: uint16 gets us up to ~18hrs, which should be plenty. If our oracle is that stale we have very large problems.
    uint16 public maxPriceUpdateSecondsAgo = 300; // 5 minutes (for now).

    /// Extending a LOC can make it so that the total duration of any given LOC may be larger than this, but no LOC may
    /// have more than this number of seconds remaining.
    uint32 public maxLocDurationSeconds = 60 * 60 * 24 * 100; // 100 days

    /// id (nonce) => Letter of Credit
    mapping(uint96 => LOC) public locs;

    /*** GOVERNABLE FIELDS ***/

    /// The ICollateral contract to use for new LOCs, after which, it is stored on the LOC referenced.
    ICollateral public collateralContract;
    // The IPriceOracle to use for all price interactions (NB: for both new and existing LOCs).
    IPriceOracle public priceOracle;
    /// If not zero, the price oracle address that is pending and is valid for governance to upgrade to after pendingPriceOracleValidTime.
    IPriceOracle public pendingPriceOracle;
    /// The time at which governance may upgrade to pendingPriceOracle.
    uint256 public pendingPriceOracleValidTime;

    /// This is to enforce a time delay for very impactful governance updates like PriceOracle updates.
    /// The owner may reasonably be changed to a 3rd party contract that handles this, at which point this might be
    /// updated to 0s, so this, itself, must be governable.
    uint256 public oracleTimeDelaySeconds = 60 * 60 * 24 * 14; // 14 days

    /// If not zero, the time delay that is pending and is valid for governance to upgrade to after pendingTimeDelaySecondsValidTime.
    uint256 public pendingOracleTimeDelaySeconds;
    /// The time at which governance may upgrade to pendingTimeDelaySeconds.
    uint256 public pendingOracleTimeDelaySecondsValidTime;

    /// Credited Token Address => token available for use as LOC credited tokens and its limits for use.
    mapping(address => CreditedToken) public creditedTokens;

    /// collateral token address => credited token address => collateral factor basis points.
    mapping(address => mapping(address => CollateralFactor)) public collateralToCreditedToCollateralFactors;

    /***********
     * GETTERS *
     ***********/

    /// Getter for locs so that contract callers may get strongly-typed LOCs.
    function getLOC(uint96 _id) public view returns (LOC memory) {
        return locs[_id];
    }

    /// Getter for creditedTokens so that contract callers may get strongly-typed CreditedTokens.
    function getCreditedToken(address _address) public view returns (CreditedToken memory) {
        return creditedTokens[_address];
    }

    /// Getter for collateralToCreditedToCollateralFactors so that contract callers may get strongly-typed CollateralFactors.
    function getCollateralFactor(
        address _collateralTokenAddress,
        address _creditedTokenAddress
    ) public view returns (CollateralFactor memory) {
        return collateralToCreditedToCollateralFactors[_collateralTokenAddress][_creditedTokenAddress];
    }

    /***********
     * STRUCTS *
     ***********/

    struct CreditedToken {
        uint256 minPerLOC;
        uint256 maxPerLOC;
        uint256 globalMaxInUse;
        uint256 globalAmountInUse;
    }

    struct CreditedTokenConfig {
        address tokenAddress;
        uint256 minPerLOC;
        uint256 maxPerLOC;
        uint256 globalMaxInUse;
    }

    struct CollateralFactor {
        uint16 creationCollateralFactorBasisPoints;
        uint16 collateralFactorBasisPoints;
        uint16 liquidatorIncentiveBasisPoints;
    }

    struct AssetPairCollateralFactor {
        address collateralTokenAddress;
        address creditedTokenAddress;
        CollateralFactor collateralFactor;
    }

    struct LOC {
        uint96 collateralId;
        address creator;
        // --- storage slot separator
        address beneficiary;
        // NB: uint32 gets us to the year 2106. If we hit that, redeploy.
        uint32 expirationTimestamp;
        uint16 collateralFactorBasisPoints;
        uint16 liquidatorIncentiveBasisPoints;
        // --- storage slot separator
        ICollateral collateralContract;
        address collateralTokenAddress;
        uint256 collateralTokenAmount;
        uint256 claimableCollateral;
        address creditedTokenAddress;
        uint256 creditedTokenAmount;
    }

    struct LiquidationContext {
        bool locUnhealthy;
        uint256 creditedTokenAmountToReceive;
        uint256 liquidationAmount;
        uint256 liquidatorFeeAmount;
        uint256 collateralToClaimAndSendLiquidator;
    }

    /*************
     * FUNCTIONS *
     *************/

    /**
     * @notice Deploys the `LetterOfCredit` contract, setting the necessary configuration parameters defining how it may
     * be used.
     * @param _collateralContract The ICollateral contract to use for collateral.
     * @param _priceOracle The IPriceOracle contract to use for oracle prices.
     * @param _creditedTokens The tokens to support as the Credited Token for Letters of Credit.
     * @param _assetPairCollateralFactors The asset pair collateral factors.
     */
    constructor(
        ICollateral _collateralContract,
        IPriceOracle _priceOracle,
        CreditedTokenConfig[] memory _creditedTokens,
        AssetPairCollateralFactor[] memory _assetPairCollateralFactors
    ) Ownable(msg.sender) {
        _upsertCreditedTokensAsOwner(_creditedTokens);
        _upsertCollateralFactorsAsOwner(_assetPairCollateralFactors);

        collateralContract = _collateralContract;
        priceOracle = _priceOracle;
    }

    /**
     * @notice Creates a LOC with the caller as the creator.
     * @param _beneficiary The beneficiary of the LOC.
     * @param _collateralTokenAddress The token address of the collateral token.
     * @param _collateralTokenAmount The amount of collateral to be locked.
     * @param _creditedTokenAddress The token address of the credited token.
     * @param _creditedTokenAmount The face value amount of the LOC.
     * @param _expirationTimestamp The expiration time of the LOC.
     * @param _oraclePriceUpdate (optional) The opaque bytes of the oracle price update to be processed. If not
     * provided, the existing oracle price must not be stale, or the transaction will revert.
     */
    function createLOC(
        address _beneficiary,
        address _collateralTokenAddress,
        uint256 _collateralTokenAmount,
        address _creditedTokenAddress,
        uint256 _creditedTokenAmount,
        uint32 _expirationTimestamp,
        bytes calldata _oraclePriceUpdate
    ) external payable refundExcess nonReentrant {
        if (_collateralTokenAddress == _creditedTokenAddress) {
            if (_collateralTokenAmount != _creditedTokenAmount) revert InvalidConvertedLOCParameters();
            _createConvertedLOC(
                msg.sender,
                _beneficiary,
                _collateralTokenAddress,
                _collateralTokenAmount,
                _expirationTimestamp
            );
            return;
        }

        Pricing.OraclePrice memory price;

        if (_oraclePriceUpdate.length > 0) {
            price = priceOracle.updatePrice{value: msg.value}(
                _collateralTokenAddress,
                _creditedTokenAddress,
                _oraclePriceUpdate
            );
        } else {
            price = priceOracle.getPrice(_collateralTokenAddress, _creditedTokenAddress);
        }

        _createLOC(
            msg.sender,
            _beneficiary,
            _collateralTokenAddress,
            _collateralTokenAmount,
            _creditedTokenAddress,
            _creditedTokenAmount,
            _expirationTimestamp,
            price
        );
    }

    /**
     * @notice Creates a new LOC from an expired LOC, releasing the old LOC and repurposing its collateral.
     * @dev This mainly exists as a cheaper way to reuse collateral.
     * @param _locId The ID of the existing expired LOC to releasing and from which to reuse collateral.
     * @param _expirationTimestamp The expiration time of the LOC.
     * @param _beneficiary The beneficiary of the LOC.
     * @param _oraclePriceUpdate (optional) The oracle price update to use in LOC collateral factor validation. If this
     * is not provided, the most recent price will be fetched and validated against recency constraints.
     */
    function createLOCFromExpired(
        uint96 _locId,
        address _beneficiary,
        uint32 _expirationTimestamp,
        bytes memory _oraclePriceUpdate
    ) external payable refundExcess nonReentrant {
        LOC memory loc = locs[_locId];
        uint256 creditedTokenAmount = loc.creditedTokenAmount;

        if (creditedTokenAmount == 0) revert LOCNotFound(_locId);
        if (msg.sender != loc.creator) revert AddressUnauthorizedForLOC(msg.sender, _locId);
        if (_expirationTimestamp <= block.timestamp) revert LOCExpired(0, _expirationTimestamp);
        if (loc.expirationTimestamp > block.timestamp) revert LOCNotExpired(_locId);
        if (_expirationTimestamp - block.timestamp > maxLocDurationSeconds)
            revert MaxLOCDurationExceeded(maxLocDurationSeconds, _expirationTimestamp);

        // NB: would put loc.collateralTokenAmount on the stack as well, but then compilation fails unless we use experimental compilation flag --viaIR.
        // If deemed safe, put this on the stack as well for savings of ~500 gas.
        address creditedTokenAddress = loc.creditedTokenAddress;
        address collateralTokenAddress = loc.collateralTokenAddress;

        delete locs[_locId];
        emit LOCCanceled(_locId);

        if (creditedTokenAddress != collateralTokenAddress) {
            Pricing.OraclePrice memory price;
            if (_oraclePriceUpdate.length > 0) {
                price = priceOracle.updatePrice{value: msg.value}(
                    collateralTokenAddress,
                    creditedTokenAddress,
                    _oraclePriceUpdate
                );
            } else {
                price = priceOracle.getPrice(collateralTokenAddress, creditedTokenAddress);
            }
            _validatePricePublishTime(uint32(price.publishTime));
            _validateAndUpdateCreditedTokenUsageForLOCCreation(creditedTokenAddress, creditedTokenAmount, true);
            _validateLOCCreationCollateralFactor(
                collateralTokenAddress,
                loc.collateralTokenAmount,
                creditedTokenAddress,
                creditedTokenAmount,
                price
            );
        }

        _persistAndEmitNewLOCCreated(
            loc.collateralId,
            msg.sender,
            _beneficiary,
            collateralTokenAddress,
            loc.collateralTokenAmount,
            loc.claimableCollateral,
            creditedTokenAddress,
            creditedTokenAmount,
            _expirationTimestamp
        );
    }

    /**
     * @notice Redeems the referenced LOC, transferring the LOC's value to the specified destination address.
     * Note: this can only be called by the beneficiary or with valid beneficiary authorization.
     * @dev If `_creditedAmountToRedeem` is the full credited amount, any collateral that was not used in redemption
     * will be canceled to the `ICollateral` contract. If `_creditedAmountToRedeem` is not the full amount, this LOC
     * will remain intact with the remaining credited amount and collateral.
     * @param _locId The ID of the loc to redeem on behalf of the beneficiary.
     * @param _creditedAmountToRedeem The amount to redeem.
     * @param _destinationAddress The address to which redeemed assets will be sent.
     * @param _iLiquidatorToUse (optional) The ILiquidator to use for liquidation if required and not liquidating
     * directly from the assets of `msg.sender`.
     * @param _oraclePriceUpdate (optional) The oracle price update to be used if liquidation is required.
     * @param _beneficiaryAuthorization (optional) The signed authorization of the beneficiary to cancel the LOC.
     */
    function redeemLOC(
        uint96 _locId,
        uint256 _creditedAmountToRedeem,
        address _destinationAddress,
        address _iLiquidatorToUse,
        bytes calldata _oraclePriceUpdate,
        bytes memory _beneficiaryAuthorization
    ) external payable refundExcess nonReentrant {
        LOC memory loc = locs[_locId];

        if (msg.sender != loc.beneficiary) {
            if (_beneficiaryAuthorization.length > 0) {
                // NB: amount remaining to prevent signature replay.
                bytes memory args = abi.encodePacked(
                    _creditedAmountToRedeem,
                    loc.creditedTokenAmount,
                    _destinationAddress
                );
                _validateAuthorizationOrRevert(
                    _locId,
                    loc.beneficiary,
                    Operation.RedeemLOC,
                    args,
                    _beneficiaryAuthorization
                );
            } else {
                revert AddressUnauthorizedForLOC(msg.sender, _locId);
            }
        }

        _redeemLOC(_locId, loc, _creditedAmountToRedeem, _destinationAddress, _iLiquidatorToUse, _oraclePriceUpdate);
    }

    /**
     * @notice Cancels the referenced LOC, releasing any reserved collateral, returning any converted amount to the
     * creator, and purging the LOC from storage.
     * Note: this may only be called by the LOC beneficiary or with valid beneficiary authorization unless the LOC has
     * expired.
     * @param _locId The ID of the LOC to cancel.
     * @param _beneficiaryAuthorization (optional) The signed authorization of the beneficiary to cancel the LOC.
     */
    function cancelLOC(uint96 _locId, bytes memory _beneficiaryAuthorization) external nonReentrant {
        LOC memory loc = locs[_locId];
        if (msg.sender != loc.beneficiary && loc.expirationTimestamp > block.timestamp) {
            if (_beneficiaryAuthorization.length > 0) {
                _validateAuthorizationOrRevert(
                    _locId,
                    loc.beneficiary,
                    Operation.CancelLOC,
                    bytes(""),
                    _beneficiaryAuthorization
                );
            } else {
                revert AddressUnauthorizedForLOC(msg.sender, _locId);
            }
        }

        _cancelLOC(_locId, loc);
    }

    /**
     * @notice Extends the referenced LOC so that its expire time is increased to `newExpirationTimestamp`.
     * @param _locId The ID of the LOC to extend.
     * @param _newExpirationTimestamp The new expiration time of the LOC. Must be greater than the existing expiration time.
     */
    function extendLOC(uint96 _locId, uint32 _newExpirationTimestamp) external {
        LOC memory loc = locs[_locId];
        if (loc.creditedTokenAmount == 0) revert LOCNotFound(_locId);
        if (msg.sender != loc.creator) revert AddressUnauthorizedForLOC(msg.sender, _locId);

        uint32 oldExpirationTimestamp = loc.expirationTimestamp;
        if (_newExpirationTimestamp <= oldExpirationTimestamp)
            revert InvalidLOCExtensionTimestamp(_locId, _newExpirationTimestamp);
        if (oldExpirationTimestamp <= block.timestamp) revert LOCExpired(_locId, oldExpirationTimestamp);
        if (_newExpirationTimestamp - block.timestamp > maxLocDurationSeconds)
            revert MaxLOCDurationExceeded(maxLocDurationSeconds, _newExpirationTimestamp);

        if (loc.collateralTokenAddress != loc.creditedTokenAddress) {
            uint16 liquidatorIncentiveBP = collateralToCreditedToCollateralFactors[loc.collateralTokenAddress][
                loc.creditedTokenAddress
            ].liquidatorIncentiveBasisPoints;
            if (liquidatorIncentiveBP > loc.liquidatorIncentiveBasisPoints)
                revert LiquidatorIncentiveChanged(loc.liquidatorIncentiveBasisPoints, liquidatorIncentiveBP);
        }

        locs[_locId].expirationTimestamp = _newExpirationTimestamp;

        emit LOCExtended(_locId, oldExpirationTimestamp, _newExpirationTimestamp);
    }

    /**
     * @notice Adds/removes collateral to/from the specified LOC.
     * @dev Note: collateral may only be removed from a LOC if the resulting collateral factor is at most the creation
     * collateral factor for the asset pair (i.e. a new LOC could be created with the resulting collateral amount).
     * @dev Only the creator may invoke this operation, as it's their collateral.
     * @param _locId The ID of the LOC for which collateral should be modified.
     * @param _byAmount The signed amount by which the collateral should be modified (add if positive, remove if negative).
     * @param _oraclePriceUpdate (optional) The oracle price update to use if removing collateral to make sure the
     * resulting amount of collateral is sufficient.
     */
    function modifyLOCCollateral(
        uint96 _locId,
        int256 _byAmount,
        bytes calldata _oraclePriceUpdate
    ) external payable refundExcess nonReentrant {
        LOC memory loc = locs[_locId];

        if (_byAmount == 0) revert NoOp();
        if (loc.creditedTokenAmount == 0) revert LOCNotFound(_locId);
        if (msg.sender != loc.creator) revert AddressUnauthorizedForLOC(msg.sender, _locId);
        if (loc.collateralTokenAddress == loc.creditedTokenAddress) revert LOCAlreadyConverted(_locId);

        // Update underlying collateral.
        (uint256 newCollateralAmount, uint256 newClaimableAmount) = loc.collateralContract.modifyCollateralReservation(
            loc.collateralId,
            _byAmount
        );

        if (_byAmount <= 0) {
            if (uint256(-_byAmount) >= loc.collateralTokenAmount)
                revert InsufficientCollateral(uint256(_byAmount), loc.collateralTokenAmount);

            uint256 requiredCollateralFactorBasisPoints = collateralToCreditedToCollateralFactors[
                loc.collateralTokenAddress
            ][loc.creditedTokenAddress].creationCollateralFactorBasisPoints;
            if (requiredCollateralFactorBasisPoints == 0)
                revert AssetPairUnauthorized(loc.collateralTokenAddress, loc.creditedTokenAddress);

            Pricing.OraclePrice memory price;
            if (_oraclePriceUpdate.length > 0) {
                price = priceOracle.updatePrice{value: msg.value}(
                    loc.collateralTokenAddress,
                    loc.creditedTokenAddress,
                    _oraclePriceUpdate
                );
            } else {
                price = priceOracle.getPrice(loc.collateralTokenAddress, loc.creditedTokenAddress);
            }
            _validatePricePublishTime(uint32(price.publishTime));

            uint16 cfBasisPoints = Pricing.collateralFactorInBasisPoints(
                newCollateralAmount,
                loc.creditedTokenAmount,
                price
            );
            if (cfBasisPoints > requiredCollateralFactorBasisPoints)
                revert InsufficientCollateral(requiredCollateralFactorBasisPoints, cfBasisPoints);
        }

        // Update storage.
        locs[_locId].collateralTokenAmount = newCollateralAmount;
        locs[_locId].claimableCollateral = newClaimableAmount;

        emit LOCCollateralModified(_locId, loc.collateralTokenAmount, newCollateralAmount, newClaimableAmount);
    }

    enum Operation {
        IntentionallyUnused, // 0
        CancelLOC, // 1
        RedeemLOC, // 2
        ConvertLOC // 3
    }

    /*****************
     * ILiquidatable *
     *****************/

    /**
     * @inheritdoc ILiquidatable
     */
    function convertLOC(
        uint96 _locId,
        address _liquidatorToUse,
        bytes calldata _oraclePriceUpdate,
        bytes calldata _creatorAuthorization
    ) external payable refundExcess nonReentrant {
        LOC memory loc = locs[_locId];

        address senderOrAuthorizer = msg.sender;
        if (msg.sender != loc.creator) {
            // NB: If not creator and there is an authorization provided, it MUST be valid, even if the LOC is unhealthy.
            if (_creatorAuthorization.length > 0) {
                _validateAuthorizationOrRevert(
                    _locId,
                    loc.creator,
                    Operation.ConvertLOC,
                    bytes(""),
                    _creatorAuthorization
                );

                senderOrAuthorizer = loc.creator;
            }
        }

        _liquidateLOCCollateral(
            _locId,
            loc.creditedTokenAmount,
            _liquidatorToUse,
            senderOrAuthorizer,
            _oraclePriceUpdate,
            address(0)
        );
    }

    /************************
     * Governance Functions *
     ************************/

    /**
     * @notice Upserts the supported `AssetPairCollateralFactors`, modifying if present, adding new otherwise.
     * Note: setting the creation collateral factor to 0 effectively disables future use of an asset pair.
     * @param _assetPairCollateralFactors The asset pair collateral factors to update
     */
    function upsertCollateralFactors(
        AssetPairCollateralFactor[] calldata _assetPairCollateralFactors
    ) external onlyOwner {
        _upsertCollateralFactorsAsOwner(_assetPairCollateralFactors);
    }

    /**
     * @notice Updates the supported `CreditedTokens` and their limits.
     * Note: setting max per LOC or global max to 0 effectively disables a CreditedToken.
     * @param _creditedTokens The credited tokens to add/modify.
     */
    function upsertCreditedTokens(CreditedTokenConfig[] calldata _creditedTokens) external onlyOwner {
        _upsertCreditedTokensAsOwner(_creditedTokens);
    }

    /**
     * @notice Updates the maximum age of a valid oracle price update.
     * @param _maxPriceUpdateSecondsAgo The new value.
     */
    function updateMaxPriceUpdateSecondsAgo(uint16 _maxPriceUpdateSecondsAgo) external onlyOwner {
        if (_maxPriceUpdateSecondsAgo < 30 || _maxPriceUpdateSecondsAgo > 3600)
            revert InvalidMaxPriceUpdateSecondsAgo(30, 3600, _maxPriceUpdateSecondsAgo);

        emit MaxPriceUpdateSecondsAgoUpdated(maxPriceUpdateSecondsAgo, _maxPriceUpdateSecondsAgo);
        maxPriceUpdateSecondsAgo = _maxPriceUpdateSecondsAgo;
    }

    /**
     * @notice Updates the supported `maxLocDurationSeconds` field.
     * @param _newMaxLocDurationSeconds The new value.
     */
    function updateMaxLocDurationSeconds(uint32 _newMaxLocDurationSeconds) external onlyOwner {
        emit MaxLocDurationSecondsUpdated(maxLocDurationSeconds, _newMaxLocDurationSeconds);
        maxLocDurationSeconds = _newMaxLocDurationSeconds;
    }

    /**
     * @notice Upgrades the `ICollateral` contract used to back new LOCs.
     * Note: Existing LOCs will continue to use the ICollateral contract that they were created with.
     * @param _collateralContract The new ICollateral contract to use.
     */
    function upgradeCollateralContract(ICollateral _collateralContract) public onlyOwner {
        emit CollateralAddressUpgraded(address(collateralContract), address(_collateralContract));
        collateralContract = _collateralContract;

        // NB: if the _collateralContract is an EOA, the transaction will revert without a reason.
        try IERC165(address(_collateralContract)).supportsInterface(type(ICollateral).interfaceId) returns (
            bool supported
        ) {
            if (!supported) revert InvalidUpgradeContract();
        } catch (bytes memory /*lowLevelData*/) {
            revert InvalidUpgradeContract();
        }
    }

    /**
     * @notice Upgrades the `priceOracle` if the provided `_newPriceOracle` has been pending long enough. If no price
     * oracle upgrade is pending or the provided `_newPriceOracle` does not match the pending one, it updates the
     * `pendingPriceOracle` and the `pendingPriceOracleValidTime` so that an upgrade is permitted after a time delay.
     * Notes:
     *  * If `timeDelaySeconds` is set to 0, none of the pending state variables are taken into account.
     *  * Calling this with a `_newPriceOracle` of `0x0` revokes an existing pending upgrade (if `timeDelaySeconds` is not 0).
     * @param _newPriceOracle The new IPriceOracle contract to upgrade.
     */
    function upgradePriceOracle(IPriceOracle _newPriceOracle) public onlyOwner {
        if (oracleTimeDelaySeconds == 0) {
            // If there's no time delay, update immediately, ignoring pending state.
            if (_newPriceOracle == priceOracle) revert NoOp();
            if (_newPriceOracle == IPriceOracle(address(0))) revert InvalidZeroAddress();

            emit PriceOracleUpgraded(priceOracle, _newPriceOracle);

            priceOracle = _newPriceOracle;
            pendingPriceOracleValidTime = 0;
            pendingPriceOracle = IPriceOracle(address(0));
        } else if (_newPriceOracle == IPriceOracle(address(0))) {
            // Revoke pending if new address is zero and there is a pending upgrade.
            if (pendingPriceOracle == IPriceOracle(address(0))) revert InvalidZeroAddress();

            pendingPriceOracleValidTime = 0;
            pendingPriceOracle = IPriceOracle(address(0));

            emit PriceOracleUpgradeRevoked();
            // Return so we don't revert on the supportsInterface check below.
            return;
        } else if (pendingPriceOracle != _newPriceOracle) {
            // Add pending upgrade if new oracle address is not already pending.
            if (_newPriceOracle == priceOracle) revert NoOp();

            uint256 validTime = block.timestamp + oracleTimeDelaySeconds;
            pendingPriceOracleValidTime = validTime;
            pendingPriceOracle = _newPriceOracle;

            emit PriceOracleUpgradePending(_newPriceOracle, validTime);
        } else if (block.timestamp >= pendingPriceOracleValidTime) {
            // Execute pending upgrade if time delay is satisfied.
            emit PriceOracleUpgraded(priceOracle, _newPriceOracle);

            priceOracle = _newPriceOracle;
            pendingPriceOracle = IPriceOracle(address(0));
            pendingPriceOracleValidTime = 0;
        } else {
            revert UpdateNotValidYet(pendingPriceOracleValidTime);
        }

        // NB: if the _newPriceOracle is an EOA, the transaction will revert without a reason.
        try IERC165(address(_newPriceOracle)).supportsInterface(type(IPriceOracle).interfaceId) returns (
            bool supported
        ) {
            if (!supported) revert InvalidUpgradeContract();
        } catch (bytes memory /*lowLevelData*/) {
            revert InvalidUpgradeContract();
        }
    }

    /**
     * @notice Updates the `timeDelaySeconds` if the provided `_newValue` has been pending long enough. If no time delay
     * is pending or the provided `_newValue` does not match the pending one, it updates the `pendingTimeDelaySeconds`
     * and the `pendingTimeDelaySecondsValidTime` so that an update is permitted after a time delay.
     * Notes:
     *  * If timeDelaySeconds is set to 0, none of the pending state variables are taken into account.
     *  * Executing this function with a `_newValue` of `0` revokes an existing pending upgrade unless.
     * @param _newValue The new time delay to mark as pending or update to.
     */
    function updateOracleTimeDelay(uint256 _newValue) public onlyOwner {
        if (oracleTimeDelaySeconds == 0) {
            // If there's no time delay, update immediately, ignoring pending state.
            if (oracleTimeDelaySeconds == _newValue) revert NoOp();

            emit OracleTimeDelayUpdated(oracleTimeDelaySeconds, _newValue);

            oracleTimeDelaySeconds = _newValue;
        } else if (pendingOracleTimeDelaySeconds != _newValue || pendingOracleTimeDelaySecondsValidTime == 0) {
            // Add pending upgrade if new time is not already pending.
            if (oracleTimeDelaySeconds == _newValue) revert NoOp();

            uint256 validTime = block.timestamp + oracleTimeDelaySeconds;
            pendingOracleTimeDelaySecondsValidTime = validTime;
            pendingOracleTimeDelaySeconds = _newValue;

            emit OracleTimeDelayUpdatePending(_newValue, validTime);
        } else if (block.timestamp >= pendingOracleTimeDelaySecondsValidTime) {
            // Execute pending upgrade if time delay is satisfied.
            emit OracleTimeDelayUpdated(oracleTimeDelaySeconds, _newValue);

            oracleTimeDelaySeconds = _newValue;
            pendingOracleTimeDelaySeconds = 0;
            pendingOracleTimeDelaySecondsValidTime = 0;
        } else {
            revert UpdateNotValidYet(pendingOracleTimeDelaySecondsValidTime);
        }
    }

    /*********************
     * Private Functions *
     *********************/

    /**
     * @notice Creates a "converted" LOC, which is just a LOC where the credited asset is the collateral asset (1:1).
     * @param _creator The transaction sender and creator of the LOC.
     * @param _beneficiary The beneficiary of the LOC.
     * @param _tokenAddress The token address of the credited and collateral asset.
     * @param _creditedAmount The face value of the LOC.
     * @param _expirationTimestamp The expiration time of the LOC.
     */
    function _createConvertedLOC(
        address _creator,
        address _beneficiary,
        address _tokenAddress,
        uint256 _creditedAmount,
        uint32 _expirationTimestamp
    ) private {
        if (_expirationTimestamp <= block.timestamp) revert LOCExpired(0, _expirationTimestamp);
        if (_expirationTimestamp - block.timestamp > maxLocDurationSeconds)
            revert MaxLOCDurationExceeded(maxLocDurationSeconds, _expirationTimestamp);

        // NB: reserveClaimableCollateral because we need to guarantee _creditedAmount is available for claim.
        // See ICollateral.reserve* for more info on different reservation options.
        (uint96 collateralId, uint256 totalAmountReserved) = collateralContract.reserveClaimableCollateral(
            _creator,
            _tokenAddress,
            _creditedAmount
        );

        /*** Create LOC ***/
        uint96 locId = ++locNonce;
        locs[locId] = LOC(
            collateralId,
            _creator,
            _beneficiary,
            _expirationTimestamp,
            0, // Not liquidatable
            0, // Not liquidatable
            collateralContract,
            _tokenAddress,
            totalAmountReserved,
            _creditedAmount,
            _tokenAddress,
            _creditedAmount
        );

        emit LOCCreated(
            _creator,
            _beneficiary,
            address(collateralContract),
            _tokenAddress,
            totalAmountReserved,
            _creditedAmount,
            _expirationTimestamp,
            0,
            0,
            _tokenAddress,
            _creditedAmount,
            locId
        );
    }

    /**
     * @notice Creates a LOC with the caller as the creator with the specified parameters.
     * @param _creator The creator of the LOC (assumed to be validated by the caller of this function).
     * @param _beneficiary The beneficiary of the LOC.
     * @param _collateralTokenAddress The token address of the collateral token.
     * @param _collateralTokenAmount The amount of collateral to be locked.
     * @param _creditedTokenAddress The token address of the credited token.
     * @param _creditedTokenAmount The face value amount of the LOC.
     * @param _expirationTimestamp The expiration time of the LOC.
     * @param _price (optional) The oracle price to use for LOC creation calculations.
     */
    function _createLOC(
        address _creator,
        address _beneficiary,
        address _collateralTokenAddress,
        uint256 _collateralTokenAmount,
        address _creditedTokenAddress,
        uint256 _creditedTokenAmount,
        uint32 _expirationTimestamp,
        Pricing.OraclePrice memory _price
    ) private {
        if (_expirationTimestamp <= block.timestamp) revert LOCExpired(0, _expirationTimestamp);
        if (_expirationTimestamp - block.timestamp > maxLocDurationSeconds)
            revert MaxLOCDurationExceeded(maxLocDurationSeconds, _expirationTimestamp);

        _validatePricePublishTime(uint32(_price.publishTime));
        _validateAndUpdateCreditedTokenUsageForLOCCreation(_creditedTokenAddress, _creditedTokenAmount, false);
        _validateLOCCreationCollateralFactor(
            _collateralTokenAddress,
            _collateralTokenAmount,
            _creditedTokenAddress,
            _creditedTokenAmount,
            _price
        );

        (uint96 collateralId, uint256 claimableCollateral) = collateralContract.reserveCollateral(
            _creator,
            _collateralTokenAddress,
            _collateralTokenAmount
        );

        _persistAndEmitNewLOCCreated(
            collateralId,
            _creator,
            _beneficiary,
            _collateralTokenAddress,
            _collateralTokenAmount,
            claimableCollateral,
            _creditedTokenAddress,
            _creditedTokenAmount,
            _expirationTimestamp
        );
    }

    /**
     * @notice Persists new LOC and emits LOCCreated event.
     * This is called in shared LOC creation flows to maintain consistency.
     * @param _collateralId The ID of the collateral reservation for the LOC to be persisted.
     * @param _creator The creator of the LOC (assumed to be validated by the caller of this function).
     * @param _beneficiary The beneficiary of the LOC.
     * @param _collateralTokenAddress The token address of the collateral token.
     * @param _collateralTokenAmount The amount of collateral to be locked.
     * @param _claimableCollateral The amount of the CollateralReservation that is claimable.
     * This will be less than _collateralTokenAmount due to collateral withdrawal fees.
     * @param _creditedTokenAddress The token address of the credited token.
     * @param _creditedTokenAmount The face value amount of the LOC.
     * @param _expirationTimestamp The expiration time of the LOC.
     */
    function _persistAndEmitNewLOCCreated(
        uint96 _collateralId,
        address _creator,
        address _beneficiary,
        address _collateralTokenAddress,
        uint256 _collateralTokenAmount,
        uint256 _claimableCollateral,
        address _creditedTokenAddress,
        uint256 _creditedTokenAmount,
        uint32 _expirationTimestamp
    ) private {
        uint16 collateralFactorBasisPoints = collateralToCreditedToCollateralFactors[_collateralTokenAddress][
            _creditedTokenAddress
        ].collateralFactorBasisPoints;
        uint16 liquidatorIncentiveBasisPoints = collateralToCreditedToCollateralFactors[_collateralTokenAddress][
            _creditedTokenAddress
        ].liquidatorIncentiveBasisPoints;

        /*** Create LOC ***/
        uint96 locId = ++locNonce;
        locs[locId] = LOC(
            _collateralId,
            _creator,
            _beneficiary,
            _expirationTimestamp,
            collateralFactorBasisPoints,
            liquidatorIncentiveBasisPoints,
            collateralContract,
            _collateralTokenAddress,
            _collateralTokenAmount,
            _claimableCollateral,
            _creditedTokenAddress,
            _creditedTokenAmount
        );

        emit LOCCreated(
            _creator,
            _beneficiary,
            address(collateralContract),
            _collateralTokenAddress,
            _collateralTokenAmount,
            _claimableCollateral,
            _expirationTimestamp,
            collateralFactorBasisPoints,
            liquidatorIncentiveBasisPoints,
            _creditedTokenAddress,
            _creditedTokenAmount,
            locId
        );
    }

    /**
     * @dev Helper function to mark the provided LOC as converted, updating its fields in storage.
     * @param _locId The ID of the LOC in question.
     * @param _initiatorAddress The address of the party that initiated conversion.
     * @param _liquidatorAddress The address of the liquidator used to trade collateral asset for credited asset.
     * @param _loc The LOC being converted.
     * @param _liquidationContext The `LiquidationContext` calculated for the conversion in question.
     */
    function _markLOCConverted(
        uint96 _locId,
        address _initiatorAddress,
        address _liquidatorAddress,
        LOC memory _loc,
        LiquidationContext memory _liquidationContext
    ) private {
        LOC storage storedLoc = locs[_locId];

        storedLoc.collateralTokenAmount = _liquidationContext.creditedTokenAmountToReceive;
        storedLoc.creditedTokenAmount = _liquidationContext.creditedTokenAmountToReceive;
        storedLoc.collateralTokenAddress = _loc.creditedTokenAddress;
        storedLoc.claimableCollateral = 0;
        storedLoc.collateralFactorBasisPoints = 0;
        storedLoc.liquidatorIncentiveBasisPoints = 0;
        storedLoc.collateralId = 0;
        storedLoc.collateralContract = ICollateral(address(0));

        emit LOCConverted(
            _locId,
            _initiatorAddress,
            _liquidatorAddress,
            _liquidationContext.liquidationAmount,
            _liquidationContext.liquidatorFeeAmount,
            _liquidationContext.creditedTokenAmountToReceive
        );
    }

    /**
     * @dev Helper function to mark the provided LOC as partially liquidated, updating its fields in storage.
     * @param _locId The ID of the LOC in question.
     * @param _initiatorAddress The address of the party that initiated partial liquidation.
     * @param _liquidatorAddress The address of the liquidator used to trade collateral asset for credited asset.
     * @param _collateralUsed The amount of collateral that was used in this partial liquidation. Note: this is more
     * than the claimable collateral that was used, which is _liquidationContext.collateralToClaimAndSendLiquidator.
     * @param _loc The LOC being partially liquidated.
     * @param _liquidationContext The `LiquidationContext` calculated for the liquidation in question.
     */
    function _markLOCPartiallyLiquidated(
        uint96 _locId,
        address _initiatorAddress,
        address _liquidatorAddress,
        uint256 _collateralUsed,
        LOC memory _loc,
        LiquidationContext memory _liquidationContext
    ) private {
        LOC storage storedLoc = locs[_locId];

        storedLoc.collateralTokenAmount = _loc.collateralTokenAmount - _collateralUsed;

        storedLoc.claimableCollateral =
            _loc.claimableCollateral -
            _liquidationContext.collateralToClaimAndSendLiquidator;
        storedLoc.creditedTokenAmount = _loc.creditedTokenAmount - _liquidationContext.creditedTokenAmountToReceive;

        emit LOCPartiallyLiquidated(
            _locId,
            _initiatorAddress,
            _liquidatorAddress,
            _liquidationContext.liquidationAmount,
            _liquidationContext.liquidatorFeeAmount,
            _liquidationContext.creditedTokenAmountToReceive
        );
    }

    /**
     * @dev Liquidates LOC collateral required to receive _requiredCreditedAmount, as determined by the oracle price.
     * Note: if the _requiredCreditedAmount is the full credited amount of the LOC, it will mark the LOC as converted.
     * @param _locId The ID of the LOC in question.
     * @param _requiredCreditedAmount The credited amount required as a result of liquidation.
     * @param _iLiquidatorToUse The liquidator to use to swap collateral for credited asset.
     * Note: this should be the zero address if the caller will swap with this contract directly.
     * @param _senderOrAuthorizer The caller and/or authorizer of this call. Relevant if the LOC is not unhealthy.
     * @param _oraclePriceUpdate The oracle price update bytes necessary to publish and read an updated oracle price.
     * @param _authorizedRedeemDestinationAddress Set to the address to which the credited token will be sent if this
     * is being called from redeemLOC(...).
     * @return _collateralUsed The amount of the reserved collateral that was used in conversion.
     * @return _claimableCollateralUsed The amount of the claimable collateral that was used in conversion.
     */
    function _liquidateLOCCollateral(
        uint96 _locId,
        uint256 _requiredCreditedAmount,
        address _iLiquidatorToUse,
        address _senderOrAuthorizer,
        bytes calldata _oraclePriceUpdate,
        address _authorizedRedeemDestinationAddress
    ) private returns (uint256 _collateralUsed, uint256 _claimableCollateralUsed) {
        LOC memory loc = locs[_locId];

        if (loc.creditedTokenAmount == 0) revert LOCNotFound(_locId);

        address collateralTokenAddress = loc.collateralTokenAddress;
        address creditedTokenAddress = loc.creditedTokenAddress;
        bool partialRedeem = _requiredCreditedAmount != loc.creditedTokenAmount;
        if (partialRedeem && _authorizedRedeemDestinationAddress == address(0))
            revert PartialConvertWithoutRedeem(_locId);
        if (collateralTokenAddress == creditedTokenAddress) revert LOCAlreadyConverted(_locId);
        if (loc.expirationTimestamp <= block.timestamp) revert LOCExpired(_locId, loc.expirationTimestamp);

        /*** Calculate Liquidation Details ***/
        LiquidationContext memory liquidationContext = _calculateLiquidationContext(
            loc,
            _requiredCreditedAmount,
            _oraclePriceUpdate
        );
        _claimableCollateralUsed = liquidationContext.collateralToClaimAndSendLiquidator;

        if (
            !liquidationContext.locUnhealthy &&
            _senderOrAuthorizer != loc.creator &&
            _authorizedRedeemDestinationAddress == address(0)
        ) {
            revert AddressUnauthorizedForLOC(_senderOrAuthorizer, _locId);
        }

        if (
            liquidationContext.collateralToClaimAndSendLiquidator == 0 ||
            liquidationContext.creditedTokenAmountToReceive == 0
        ) {
            revert LiquidationAmountTooSmall(
                liquidationContext.collateralToClaimAndSendLiquidator,
                liquidationContext.creditedTokenAmountToReceive
            );
        }

        address liquidatorAddress;
        {
            // NB: need to pop collateralRemaining off of the stack in this closure to avoid "Stack too deep" error after.
            if (_iLiquidatorToUse != address(0)) {
                liquidatorAddress = _iLiquidatorToUse;

                // Claim collateral to this contract so liquidator may retrieve it from here in liquidate(...) call below.
                {
                    (uint256 collateralRemaining, ) = loc.collateralContract.claimCollateral(
                        loc.collateralId,
                        _claimableCollateralUsed,
                        address(this),
                        !partialRedeem
                    );
                    _collateralUsed = loc.collateralTokenAmount - collateralRemaining;
                }

                /*** Approve liquidator to withdraw the collateral from this contract ***/
                // NB: we do not verify that the liquidator actually transferred this amount in order to save gas.
                IERC20(collateralTokenAddress).approve(_iLiquidatorToUse, _claimableCollateralUsed);

                // NB: utilizing scope to free stack space and prevent "Stack too deep" compile error.
                {
                    /*** Liquidate through ILiquidator interface ***/
                    uint256 creditedBalanceBefore = IERC20(creditedTokenAddress).balanceOf(address(this));

                    /*** Liquidate ***/
                    ILiquidator(_iLiquidatorToUse).liquidate(
                        msg.sender,
                        collateralTokenAddress,
                        _claimableCollateralUsed,
                        creditedTokenAddress,
                        liquidationContext.creditedTokenAmountToReceive
                    );

                    /*** Verify the received amount is exactly the expected amount ***/
                    uint256 receivedAmount = IERC20(creditedTokenAddress).balanceOf(address(this)) -
                        creditedBalanceBefore;
                    if (receivedAmount != liquidationContext.creditedTokenAmountToReceive)
                        revert ConversionFundsReceivedMismatch(
                            liquidationContext.creditedTokenAmountToReceive,
                            receivedAmount
                        );
                }
            } else {
                liquidatorAddress = msg.sender;

                // If the redeem recipient is the sender, we don't want to claim from them just to send to them. Note matching logic in _redeemLOC(...).
                if (_authorizedRedeemDestinationAddress != msg.sender) {
                    /*** Claim credited asset from msg.sender ***/
                    IERC20(creditedTokenAddress).safeTransferFrom(
                        msg.sender,
                        address(this),
                        liquidationContext.creditedTokenAmountToReceive
                    );
                }
                {
                    /*** Claim collateral from vault and disburse directly to liquidator (original caller) ***/
                    (uint256 collateralRemaining, ) = loc.collateralContract.claimCollateral(
                        loc.collateralId,
                        _claimableCollateralUsed,
                        msg.sender,
                        !partialRedeem
                    );

                    _collateralUsed = loc.collateralTokenAmount - collateralRemaining;
                }
            }
        }

        if (partialRedeem) {
            _markLOCPartiallyLiquidated(
                _locId,
                msg.sender,
                liquidatorAddress,
                _collateralUsed,
                loc,
                liquidationContext
            );
        } else {
            _markLOCConverted(_locId, msg.sender, liquidatorAddress, loc, liquidationContext);
        }

        // Free up global credited token max headroom.
        creditedTokens[creditedTokenAddress].globalAmountInUse -= liquidationContext.creditedTokenAmountToReceive;
    }

    /**
     * Redeems the LOC in question, ignoring authorization checks with the assumption that they are handled by the caller.
     * @dev If `_creditedAmountToRedeem` is the full credited amount, any collateral that was not used in redemption
     * will be canceled to the `ICollateral` contract. If `_creditedAmountToRedeem` is not the full amount, this LOC
     * will remain intact with the remaining credited amount and collateral.
     * @param _locId The ID of the loc to redeem on behalf of the beneficiary.
     * @param _loc The LOC to redeem on behalf of the beneficiary.
     * @param _creditedTokenAmountToRedeem The amount of the credited token to redeem (may not be full LOC value).
     * @param _destinationAddress The address to which redeemed assets will be sent.
     * @param _iLiquidatorToUse (optional) The ILiquidator to use for liquidation if required and not liquidating
     * directly from the assets of `msg.sender`.
     * @param _oraclePriceUpdate (optional) The oracle price update to be used if liquidation is required.
     */
    function _redeemLOC(
        uint96 _locId,
        LOC memory _loc,
        uint256 _creditedTokenAmountToRedeem,
        address _destinationAddress,
        address _iLiquidatorToUse,
        bytes calldata _oraclePriceUpdate
    ) private {
        if (_loc.creditedTokenAmount == 0) revert LOCNotFound(_locId);
        if (_loc.expirationTimestamp <= block.timestamp) revert LOCExpired(_locId, _loc.expirationTimestamp);
        if (_creditedTokenAmountToRedeem == 0 || _creditedTokenAmountToRedeem > _loc.creditedTokenAmount)
            revert InvalidRedeemAmount(_creditedTokenAmountToRedeem, _loc.creditedTokenAmount);
        if (_destinationAddress == address(0)) revert InvalidZeroAddress();

        bool isPartialRedeem = _creditedTokenAmountToRedeem != _loc.creditedTokenAmount;

        uint256 collateralUsed = 0;
        uint256 claimableCollateralUsed = 0;

        uint256 redeemedAmount = _creditedTokenAmountToRedeem;

        /**
        Steps:
        1. Liquidate reserved collateral for credited asset if necessary.
        2. Claim collateral if it is the credited asset and has not yet been claimed.
        3. Transfer credited asset to _destinationAddress
        */

        // Liquidate collateral for credited asset if necessary. Note: This claims collateral.
        if (_loc.collateralTokenAddress != _loc.creditedTokenAddress) {
            (collateralUsed, claimableCollateralUsed) = _liquidateLOCCollateral(
                _locId,
                _creditedTokenAmountToRedeem,
                _iLiquidatorToUse,
                msg.sender,
                _oraclePriceUpdate,
                _destinationAddress
            );
        }

        if (_loc.collateralId != 0 && _loc.collateralTokenAddress == _loc.creditedTokenAddress) {
            // This means that the reserved collateral is in the credited asset.
            // Claim assets directly to _destinationAddress.
            uint256 collateralRemaining;
            uint256 claimableCollateralRemaining;
            // Claim directly to _destinationAddress
            (collateralRemaining, claimableCollateralRemaining) = _loc.collateralContract.claimCollateral(
                _loc.collateralId,
                _creditedTokenAmountToRedeem, // NB: Credited is collateral token
                _destinationAddress,
                !isPartialRedeem
            );
            collateralUsed = _loc.collateralTokenAmount - collateralRemaining;
            claimableCollateralUsed = _creditedTokenAmountToRedeem;

            if (isPartialRedeem) {
                // NB: Only update state for partial redeem because LOC storage will be deleted below for full redeem.
                LOC storage storageLOC = locs[_locId];
                storageLOC.collateralTokenAmount = collateralRemaining;
                storageLOC.claimableCollateral = claimableCollateralRemaining;
                storageLOC.creditedTokenAmount = claimableCollateralRemaining;
            }
        } else {
            uint256 transferAmount;
            // If we reach this code, we have converted necessary assets but not transferred them. Transfer assets.
            if (isPartialRedeem) {
                // NB: This line banks on the fact that we cannot partially redeem insolvent LOCs.
                transferAmount = _creditedTokenAmountToRedeem;

                if (claimableCollateralUsed == 0) {
                    // We partially redeemed a LOC that was already converted. Update the LOC state.
                    LOC storage storageLOC = locs[_locId];
                    // NB: This amount banks on the fact that we cannot partially redeem insolvent LOCs.
                    storageLOC.creditedTokenAmount = _loc.creditedTokenAmount - _creditedTokenAmountToRedeem;
                    collateralUsed = _creditedTokenAmountToRedeem;
                    storageLOC.collateralTokenAmount = _loc.collateralTokenAmount - collateralUsed;
                }
            } else {
                // NB: This should be _creditedTokenAmountToRedeem, but use locs[_locId].creditedTokenAmount in case LOC is insolvent.
                redeemedAmount = locs[_locId].creditedTokenAmount;
                transferAmount = redeemedAmount;
            }

            // Only do transfer if the destination address is not acting as the direct liquidator.
            // Otherwise we would claim the credited token from them to then transfer it to them.
            if (_loc.collateralId == 0 || _iLiquidatorToUse != address(0) || _destinationAddress != msg.sender) {
                IERC20(_loc.creditedTokenAddress).safeTransfer(_destinationAddress, transferAmount);
            }
        }

        if (!isPartialRedeem) {
            delete locs[_locId];
        }

        emit LOCRedeemed(_locId, _destinationAddress, redeemedAmount, collateralUsed, claimableCollateralUsed);
    }

    /**
     * @dev Private helper function to cancel the LOC in question.
     * Note: Assumes that caller validation has been done, but no other validation.
     * @param _locId The ID of the LOC in question.
     * @param _loc The LOC object.
     */
    function _cancelLOC(uint96 _locId, LOC memory _loc) private {
        if (_loc.creditedTokenAmount == 0) revert LOCNotFound(_locId);

        delete locs[_locId];

        if (_loc.collateralId == 0) {
            // NB: this means the LOC was converted through liquidation and the collateral has been seized by this contract.
            // When converted, the collateral amount and token are updated to be the same as the credited amount and token.
            IERC20(_loc.collateralTokenAddress).safeTransfer(_loc.creator, _loc.collateralTokenAmount);
        } else {
            _loc.collateralContract.releaseAllCollateral(_loc.collateralId);
        }

        emit LOCCanceled(_locId);

        address creditedTokenAddress = _loc.creditedTokenAddress;
        if (creditedTokenAddress != _loc.collateralTokenAddress) {
            creditedTokens[creditedTokenAddress].globalAmountInUse -= _loc.creditedTokenAmount;
        }
    }

    /**
     * @dev Validates the provided Beneficiary Authorization for the LOC and operation in question.
     * @param _locId The ID of the LOC for which the authorization should be valid.
     * @param _authorizer The address of the party that is expected to have signed the authorization.
     * @param _operation The SignatureOperation value indicating the operation for which the signature should be valid.
     * @param _operationArgs The relevant operation arguments that must be included in the signature, if there are any.
     * @param _authorization The signed authorization being validated.
     * @notice This will revert if the authorization is not valid.
     */
    function _validateAuthorizationOrRevert(
        uint96 _locId,
        address _authorizer,
        Operation _operation,
        bytes memory _operationArgs,
        bytes memory _authorization
    ) private view {
        bytes memory encoded;
        if (_operationArgs.length > 0) {
            encoded = abi.encodePacked(_operation, _locId, block.chainid, address(this), _operationArgs);
        } else {
            encoded = abi.encodePacked(_operation, _locId, block.chainid, address(this));
        }

        bytes32 locHash = MessageHashUtils.toEthSignedMessageHash(encoded);
        if (ECDSA.recover(locHash, _authorization) != _authorizer) revert InvalidSignature();
    }

    /**
     * @dev Helper function to verify the publish time of an oracle price.
     * Note: Reverts on failure.
     * @param _publishTime The publish time to validate.
     */
    function _validatePricePublishTime(uint32 _publishTime) private view {
        if (_publishTime <= block.timestamp && block.timestamp - _publishTime > maxPriceUpdateSecondsAgo)
            revert PriceUpdateStale(_publishTime, maxPriceUpdateSecondsAgo);
    }

    /**
     * @dev Validates the LOC creation collateral factor for the potential LOC with the provided parameters.
     * Note: Reverts on failure.
     * @param _collateralTokenAddress The address of the collateral token of the potential LOC.
     * @param _collateralTokenAmount The amount of the collateral token of the potential LOC.
     * @param _creditedTokenAddress The address of the credited token of the potential LOC.
     * @param _creditedTokenAmount The amount of the credited token of the potential LOC.
     * @param _price The price to use to consider collateral factor validity.
     */
    function _validateLOCCreationCollateralFactor(
        address _collateralTokenAddress,
        uint256 _collateralTokenAmount,
        address _creditedTokenAddress,
        uint256 _creditedTokenAmount,
        Pricing.OraclePrice memory _price
    ) private view {
        uint16 creationCollateralFactorBasisPoints = collateralToCreditedToCollateralFactors[_collateralTokenAddress][
            _creditedTokenAddress
        ].creationCollateralFactorBasisPoints;
        if (creationCollateralFactorBasisPoints == 0)
            revert AssetPairUnauthorized(_collateralTokenAddress, _creditedTokenAddress);

        /*** Verify Collateral Factor ***/
        uint16 currentCollateralFactorBasisPoints = Pricing.collateralFactorInBasisPoints(
            _collateralTokenAmount,
            _creditedTokenAmount,
            _price
        );

        if (
            currentCollateralFactorBasisPoints == 0 ||
            currentCollateralFactorBasisPoints > creationCollateralFactorBasisPoints
        ) revert InvalidCollateralFactor(creationCollateralFactorBasisPoints, currentCollateralFactorBasisPoints);
    }

    /**
     * @dev Validates the provided CreditedToken for use in LOC creation, reverting if invalid.
     * @param _creditedTokenAddress The address of the credited token.
     * @param _creditedTokenAmount The amount of the credited token to be used for the creation of a LOC.
     * @param _isCreatingFromExisting True if the LOC to be created exists but is no longer in use (e.g. expired).
     */
    function _validateAndUpdateCreditedTokenUsageForLOCCreation(
        address _creditedTokenAddress,
        uint256 _creditedTokenAmount,
        bool _isCreatingFromExisting
    ) private {
        CreditedToken memory creditedToken = creditedTokens[_creditedTokenAddress];
        if (_creditedTokenAmount > creditedToken.maxPerLOC)
            revert LOCCreditedTokenMaxExceeded(creditedToken.maxPerLOC, _creditedTokenAmount);

        if (_creditedTokenAmount < creditedToken.minPerLOC)
            revert LOCCreditedTokenUnderMinimum(creditedToken.minPerLOC, _creditedTokenAmount);

        if (!_isCreatingFromExisting) {
            uint256 newCreditedAmountInUse = creditedToken.globalAmountInUse + _creditedTokenAmount;
            if (newCreditedAmountInUse > creditedToken.globalMaxInUse)
                revert GlobalCreditedTokenMaxInUseExceeded(creditedToken.globalMaxInUse, newCreditedAmountInUse);

            creditedTokens[_creditedTokenAddress].globalAmountInUse = newCreditedAmountInUse;
        }
    }

    /**
     * @dev Helper function to calculate and populate the `LiquidationContext` struct of a liquidation for the provided
     * LOC with the provided oracle price.
     * @param _loc The LOC for which liquidation context is being calculated.
     * @param _requiredCreditedAmount The amount of the credited token needed as a result of liquidation.
     * @param _oraclePriceUpdate The opaque oracle bytes to use to update the oracle price prior to calculation.
     * @return The LiquidationContext struct with all the calculated fields necessary to carry out liquidation.
     */
    function _calculateLiquidationContext(
        LOC memory _loc,
        uint256 _requiredCreditedAmount,
        bytes memory _oraclePriceUpdate
    ) private returns (LiquidationContext memory) {
        Pricing.OraclePrice memory price;
        if (_oraclePriceUpdate.length > 0) {
            price = priceOracle.updatePrice{value: msg.value}(
                _loc.collateralTokenAddress,
                _loc.creditedTokenAddress,
                _oraclePriceUpdate
            );
        } else {
            price = priceOracle.getPrice(_loc.collateralTokenAddress, _loc.creditedTokenAddress);
        }
        _validatePricePublishTime(uint32(price.publishTime));

        /*** Determine if this LOC is insolvent, and if so, adjust credited amount to receive. ***/
        {
            uint256 claimableCollateralInCreditedToken = Pricing.collateralAmountInCreditedToken(
                _loc.claimableCollateral,
                price
            );

            if (claimableCollateralInCreditedToken == 0) revert CollateralAmountInCreditedTokenZero();

            uint256 maxCreditedTokenAmountToReceive = Pricing.amountBeforeFee(
                claimableCollateralInCreditedToken,
                _loc.liquidatorIncentiveBasisPoints
            );

            if (maxCreditedTokenAmountToReceive < _loc.creditedTokenAmount) {
                if (_requiredCreditedAmount != _loc.creditedTokenAmount) revert PartialRedeemInsolvent();
                // This means that the LOC is insolvent, meaning the collateral is not enough to pay all fees and LOC face value.
                // The liquidator and protocol will still get their full fees, but the beneficiary will not get LOC face value.
                // This should never happen, but if somehow it does, the beneficiary should receive as much as possible.

                // We know maxCreditedTokenAmountToReceive is all the credited we can receive using all claimable. Create a LiquidationContext representing this.
                return _createLiquidationContextUsingAllClaimableCollateral(_loc, maxCreditedTokenAmountToReceive);
            }
        }

        /*** LOC is not insolvent, so calculate liquidation amounts, leaving collateral to be received untouched. ***/

        /**
         1. get collateral value in credited
         2. calculate fraction of that being used
         3. multiply total collateral by that fraction to get collateral used
         Note: liquidationAmount below combines 2 & 3 into 1 step
         */
        uint256 collateralAmountInCreditedToken = Pricing.collateralAmountInCreditedToken(
            _loc.collateralTokenAmount,
            price
        );

        uint256 liquidationAmount = (_loc.collateralTokenAmount * _requiredCreditedAmount) /
            collateralAmountInCreditedToken;

        uint256 liquidatorFeeAmount = Pricing.percentageOf(liquidationAmount, _loc.liquidatorIncentiveBasisPoints);
        uint256 collateralToClaim = liquidationAmount + liquidatorFeeAmount;
        if (collateralToClaim > _loc.claimableCollateral) {
            // We know this LOC is solvent, but it's unhealthy enough such that calculating collateral to claim from
            // total collateral reserved loses enough precision such that it is greater than the claimable collateral.
            // In this case, we'll use all claimable collateral and convert for the full amount.
            return _createLiquidationContextUsingAllClaimableCollateral(_loc, _requiredCreditedAmount);
        }

        // NB: Truncation is fine because we're checking >= for unhealthy below
        uint256 collateralFactorBasisPoints = (_loc.creditedTokenAmount * 10_000) / collateralAmountInCreditedToken;

        return
            LiquidationContext(
                collateralFactorBasisPoints >= _loc.collateralFactorBasisPoints,
                _requiredCreditedAmount,
                liquidationAmount,
                liquidatorFeeAmount,
                collateralToClaim
            );
    }

    /**
     * @notice Calculates creates a `LiquidationContext` using all of the provided `LOC's` claimable collateral
     * specifying the provided amount of the credited asset as the expected amount to receive.
     * Note: This `LiquidationContext` is hardcoded to be unhealthy. If all of a LOC's claimable collateral is necessary
     * to trade into the credited asset, it cannot be healthy unless it is already converted.
     * @param _loc The LOC for which the returned LiquidationContext is being created.
     * @param _creditedToReceive The value that the `creditedTokenAmountToReceive` field should be set to.
     * @return The LiquidationContext.
     */
    function _createLiquidationContextUsingAllClaimableCollateral(
        LOC memory _loc,
        uint256 _creditedToReceive
    ) private pure returns (LiquidationContext memory) {
        uint256 collateralToClaim = _loc.claimableCollateral;
        uint256 collateralToTrade = Pricing.amountBeforeFee(collateralToClaim, _loc.liquidatorIncentiveBasisPoints);
        return
            LiquidationContext(
                true, // unhealthy because using all collateral means, at best, credited amount is 100% of the value of collateral, which is unhealthy in all cases.
                _creditedToReceive,
                collateralToTrade,
                collateralToClaim - collateralToTrade,
                collateralToClaim
            );
    }

    /**
     * @notice Upserts the supported `AssetPairCollateralFactors`, modifying if present, adding new otherwise.
     * Note: setting the creation collateral factor to 0 effectively disables future use of an asset pair.
     * @dev It is assumed that the caller of this function has verified that the msg.sender is the owner.
     * @param _assetPairCollateralFactors The asset pair collateral factors to update
     */
    function _upsertCollateralFactorsAsOwner(AssetPairCollateralFactor[] memory _assetPairCollateralFactors) private {
        for (uint256 i = 0; i < _assetPairCollateralFactors.length; i++) {
            AssetPairCollateralFactor memory apcf = _assetPairCollateralFactors[i];
            CollateralFactor memory cf = apcf.collateralFactor;

            uint16 liquidatorIncentiveBasisPoints = cf.liquidatorIncentiveBasisPoints;
            if (liquidatorIncentiveBasisPoints > 10_000) revert InvalidBasisPointValue(liquidatorIncentiveBasisPoints);

            uint16 creationCFBasisPoints = cf.creationCollateralFactorBasisPoints;
            if (creationCFBasisPoints > 10_000) revert InvalidBasisPointValue(creationCFBasisPoints);

            uint16 liquidationCFBasisPoints = cf.collateralFactorBasisPoints;
            if (liquidationCFBasisPoints <= creationCFBasisPoints)
                revert CollateralFactorOverlap(creationCFBasisPoints, liquidationCFBasisPoints);

            uint16 maxLiquidatorIncentive = 10_000 - liquidationCFBasisPoints;
            if (liquidatorIncentiveBasisPoints > maxLiquidatorIncentive)
                revert LiquidatorIncentiveAboveMax(maxLiquidatorIncentive, liquidatorIncentiveBasisPoints);

            address collateralAddress = apcf.collateralTokenAddress;
            address creditedAddress = apcf.creditedTokenAddress;

            collateralToCreditedToCollateralFactors[collateralAddress][creditedAddress] = cf;

            emit CollateralFactorUpdated(
                collateralAddress,
                creditedAddress,
                creationCFBasisPoints,
                liquidationCFBasisPoints,
                liquidatorIncentiveBasisPoints
            );
        }
    }

    /**
     * @notice Updates the supported `CreditedTokens` and their limits.
     * Note that setting global max in use to 0 effectively disables a CreditedToken.
     * @dev It is assumed that the caller of this function has verified that the msg.sender is the owner.
     * @param _creditedTokens The credited tokens to add/modify.
     */
    function _upsertCreditedTokensAsOwner(CreditedTokenConfig[] memory _creditedTokens) private {
        for (uint256 i = 0; i < _creditedTokens.length; i++) {
            CreditedTokenConfig memory config = _creditedTokens[i];
            uint256 minPerLOC = config.minPerLOC;
            uint256 maxPerLOC = config.maxPerLOC;
            address tokenAddress = config.tokenAddress;
            uint256 globalMaxInUse = config.globalMaxInUse;

            // NB: If disabling this credited token, should be able to zero out all state, else validate.
            if (globalMaxInUse > 0) {
                if (minPerLOC >= maxPerLOC) revert CreditedTokenMinMaxOverlap();
                if (minPerLOC == 0) revert EnabledCreditedTokenMinPerLOCZero();
            }

            creditedTokens[tokenAddress].minPerLOC = minPerLOC;
            creditedTokens[tokenAddress].maxPerLOC = maxPerLOC;
            creditedTokens[tokenAddress].globalMaxInUse = globalMaxInUse;

            emit CreditedTokenUpdated(tokenAddress, minPerLOC, maxPerLOC, globalMaxInUse);
        }
    }
}
