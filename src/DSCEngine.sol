// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {DSCPool} from "./DSCPool.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLibs.sol";

/**
 * @title DSCEngine
 * @author Samuel Muto
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg
 * This stabkecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI has no governance, no fees, and was only backed by WETH and WBTC
 *
 * Our DSC system should be always be "overcollateralized". At no point, should the value of all collateral <= the $ pegged value of all the DSC
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on MakerDAO DSS system (DAI)
 */

contract DSCEngine is ReentrancyGuard {
    ////////////
    // ERRORS //
    ////////////

    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsFine();
    error DSCEngine__HealthFactoNotImproved();

    ////////////
    // TYPES  //
    ////////////
    using OracleLib for AggregatorV3Interface;

    /////////////////////
    // STATE VARIABLES //
    /////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // this mean 10% bonus
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;
    address private immutable i_poolAddress;

    ////////////
    // EVENTS //
    ////////////

    event CollateralDeposited(address indexed sender, address indexed tokenAddress, uint256 indexed amountDeposited);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event DscBurned(address indexed sender, uint256 amount);

    ///////////////
    // MODIFIERS //
    ///////////////

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////////////////
    // FUNCTIONS                //
    //////////////////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress,
        address dscPoolAddress
    ) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
        i_poolAddress = payable(dscPoolAddress);
    }

    ///////////////////////
    //External Functions //
    ///////////////////////

    /**
     *
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToMint the amount of DSC to mint
     * @notice this function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress the collateral address to redeem
     * @param amountCollateral the amount of collateral to redeem
     * @param amountDscToBurn the amount of DSC to burn
     * this function burns DSC and redeems underlying collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amountDscToMint The amount of DSC to mint
     * @dev follows CEI
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(msg.sender, msg.sender, amount);
    }

    /**
     * @param collateral the ERC20 collateral address to liquidate from the user
     * @param user the user who has broken the health factor. their _healthfactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover the amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice for this function to work it assumes the protocol is 200% over collateralized in order for this to work.
     * @notice a known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivice the liquidators
     * For example,  if the price of collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsFine();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _sentAmountLeftToDscPool(user, i_poolAddress);
        _burnDsc(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactoNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////////
    // Private and Internal View FUnctions //
    /////////////////////////////////////////

    /**
     * @dev Low level internal function, do not call unless the function calling it is
     * checking fir health factors being broken
     */
    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountDscToBurn) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        emit DscBurned(onBehalfOf, amountDscToBurn);
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _sentAmountLeftToDscPool(address liquidatedUser, address tokenCollateral) private {
        uint256 amountCollateral = s_collateralDeposited[liquidatedUser][tokenCollateral];
        _redeemCollateral(liquidatedUser, i_poolAddress, tokenCollateral, amountCollateral);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     *
     * @param user the address of user we are checking for the health factor
     *
     * returns how close to lequidation a user is
     * if a user goes below 1, the they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0 ether) return type(uint256).max;
        uint256 healthFactor = _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
        return healthFactor;
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        private
        pure
        returns (uint256 healthFactor)
    {
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////
    // Public and External View Functions //
    ////////////////////////////////////////

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256 healthFactor)
    {
        healthFactor = _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 collateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            collateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralDeposited(address weth, address user) public view returns (uint256 collateral) {
        collateral = s_collateralDeposited[user][weth];
    }

    function getHealthFactor(address sender) external view returns (uint256 healthFactor) {
        healthFactor = _healthFactor(sender);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getDscMinted(address user) external view returns (uint256 dscMinted) {
        dscMinted = s_DscMinted[user];
    }

    function getPrecision() public pure returns (uint256 precision) {
        precision = PRECISION;
    }

    function getAdditionalFeedPrecision() public pure returns (uint256 feedPrecison) {
        feedPrecison = ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationBonus() public pure returns (uint256 bonus) {
        bonus = LIQUIDATION_BONUS;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getTokenPriceFeedAddress(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
