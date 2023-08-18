// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DSCPool} from "../../src/DSCPool.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    DecentralisedStableCoin dsc;
    DSCEngine engine;
    DSCPool pool;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address wbtc;
    address weth;
    uint256 deployerKey;

    // liquidator
    address liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    address USER = makeAddr("user");
    uint256 public amountToMint = 100 ether;
    uint256 public amountToBurn = 100 ether;

    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 private constant LIQUIDATOR_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    event CollateralDeposited(address indexed sender, address indexed tokenAddress, uint256 indexed amountDeposited);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event DscBurned(address indexed sender, uint256 amount);

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, pool, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // CONSTRUCTOR  TESTS//
    ///////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc), address(pool));
    }

    ////////////////
    // PRICE TEST //
    ////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15 ether;
        uint256 expectedUsd = 30000 ether;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assert(expectedUsd == actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 expectedWeth = 0.005 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, AMOUNT_COLLATERAL);
        assertEq(actualWeth, expectedWeth);
    }

    ////////////////////////////////
    // DEPOSIT COLLATERAL TEST    //
    ////////////////////////////////

    function testRevertsIfCollateralNotMoreThanZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.depositCollateral(weth, 0 ether);
    }

    // this test needs its owm setUp
    function testRevertsIfTranferFromFails() public {
        // Arrange - SetUp
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc), address(pool));

        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockEngine));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockEngine), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTokenAddressNotAllowed() public {
        ERC20Mock sameETH = new ERC20Mock("SAME", "SETH", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(sameETH), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralWhenWePassValidTokenAddressAndAmount() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testUpdateTheCollateralDepositedDataStructure() public depositCollateral {
        uint256 collateral = engine.getCollateralDeposited(weth, USER);
        assert(collateral == AMOUNT_COLLATERAL);
    }

    function testEmitAnEventWhenAmountDeposited() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(engine));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0 ether;
        uint256 expectedCollateralValueInUsd = 20000 ether;

        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedCollateralValueInUsd, collateralValueInUsd);
    }

    ////////////////////////////////
    // MINT_DSC FUNCTION TEST    ///
    ////////////////////////////////

    // This test needs it's own custom setUp
    function testRevertsIfMintFails() public {
        // Arrange - setUp
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc), address(pool));
        mockDsc.transferOwnership(address(mockEngine));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testRevertsWhenMintingLessThanZeroDSC() public depositCollateral {
        uint256 dscToMint = 0 ether;
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.mintDsc(dscToMint);
        vm.stopPrank();
    }

    function testRevertsToMintIfHealthFactorIsBroken() public depositCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL * ((uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision());

        vm.startPrank(USER);
        uint256 expectedHEalthFactor =
            engine.calculateHealthFactor(engine.getUsdValue(weth, AMOUNT_COLLATERAL), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHEalthFactor));
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositCollateral {
        vm.prank(USER);
        engine.mintDsc(amountToMint);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    ////////////////////////////////////////////////
    // DEPOSIT COLLATERAL AND MINT DSC FUNCTION  ///
    ////////////////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(engine.getUsdValue(weth, AMOUNT_COLLATERAL), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testDespositCollateralAndMintDsc() public {
        uint256 dscToMint = 10000 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, dscToMint);
        uint256 collateralDeposited = engine.getCollateralDeposited(weth, USER);
        uint256 dscMinted = engine.getDscMinted(USER);
        vm.stopPrank();

        assertEq(collateralDeposited, AMOUNT_COLLATERAL);
        assertEq(dscToMint, dscMinted);
    }

    modifier depositAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        _;
    }

    ///////////////////////
    // BURN DSC FUNCTION //
    ///////////////////////

    function testDscAmountToBurnMustBeMoreThanZero() public depositAndMintDsc {
        uint256 dscToBurn = 0 ether;
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.burnDsc(dscToBurn);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDsc(1);
    }

    function testCanBurnDsc() public depositAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        engine.burnDsc(amountToMint);
        vm.stopPrank();
    }

    function testEmitsAnEventWhenDscIsBurnt() public depositAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToBurn);
        vm.expectEmit(true, false, false, true, address(engine));
        emit DscBurned(USER, amountToBurn);
        engine.burnDsc(amountToBurn);
        vm.stopPrank();
    }

    ///////////////////////
    // REDEEM COLLATERAL //
    ///////////////////////

    // this test needs its own setUo
    function testRevertsIfTranferFails() public {
        // Arrange - SetUp
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc), address(pool));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockEngine));

        // Arrange - USER
        vm.startPrank(USER);
        ERC20Mock(address(mockDsc)).approve(address(mockEngine), AMOUNT_COLLATERAL);
        // Assert / Act
        mockEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfUserRedeemZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.redeemCollateral(weth, 0 ether);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE);
        vm.stopPrank();
    }

    function testEmitsAnEventWhenCollateralIsRedeemed() public depositCollateral {
        uint256 redeem = 4.23 ether;
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, redeem);
        engine.redeemCollateral(weth, redeem);
        vm.stopPrank();
    }

    // RedeemCollateralForDsc TEST

    function testMustRedeemMoreThanZero() public depositAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testRedeemCollateralForDsc() public depositAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToBurn);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, amountToBurn);
        vm.stopPrank();
    }

    ////////////////////////
    // HEALTH FACTOR TEST //
    ////////////////////////

    function testProperlyReportHealthFactor() public depositAndMintDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = engine.getHealthFactor(USER);
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositAndMintDsc {
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        assert(userHealthFactor == 0.9 ether);
    }

    ////////////////////////////////
    // LIQUIDATION FUNCTION TEST  //
    ////////////////////////////////

    // this test need its own setup
    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange- setUp
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc), address(pool));
        mockDsc.transferOwnership(address(mockEngine));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        // Arrange - liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockEngine), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockEngine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        mockDsc.approve(address(mockEngine), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH == $ 18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Act or Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactoNotImproved.selector);
        mockEngine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testRevertsIfDebtToCoverIsLessThanZero() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.liquidate(weth, liquidator, 0 ether);
    }

    function testRevertIfUsersBalanceIsGood() public depositAndMintDsc {
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsFine.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        int256 ethUsdPriceUpdated = 18e8; // 1 ETH = $ 18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdPriceUpdated);

        uint256 userHealthFactor = engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();

        uint256 userHealthFactor2 = engine.getHealthFactor(liquidator);
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, amountToMint)
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testDscPoolReceiveCollateral() public liquidated {
        uint256 dscPoolFunds = pool.getBalance(weth);
        assert(dscPoolFunds > 0);
    }

    function testUserHasNoEthAfterLiquidation() public liquidated {
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, amountToMint)
            + (engine.getTokenAmountFromUsd(weth, amountToMint) / engine.getLiquidationBonus());
        uint256 usdAmountLiquidated = engine.getUsdValue(weth, amountLiquidated);
        uint256 amountReceiveByPool = pool.getBalance(weth);
        uint256 balanceInUsd = engine.getUsdValue(weth, amountReceiveByPool);
        uint256 expectedUserCollateralValue =
            engine.getUsdValue(weth, AMOUNT_COLLATERAL) - (usdAmountLiquidated + balanceInUsd);
        (, uint256 userCollateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 hardCodedExpectedValue = 0;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValue);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = engine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }
}
