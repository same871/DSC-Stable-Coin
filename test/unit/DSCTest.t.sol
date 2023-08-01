// SPDX-License-Identifier: SMIT
pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";

contract DSCTest is Test {
    DecentralisedStableCoin dsc;
    DSCEngine engine;

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine,) = deployer.run();
    }

    function testRevertsIfAmountToMintIsLessThanOrEqualToZero() public {
        vm.prank(address(engine));
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStaleCoin__MustBeMoreThanZero.selector);
        dsc.mint(address(engine), 0 ether);
    }

    function testMintDSC() public {
        vm.prank(address(engine));
        dsc.mint(address(engine), 10 ether);
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.prank(address(engine));
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStaleCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    modifier mintDSC() {
        vm.prank(address(engine));
        dsc.mint(address(engine), 10 ether);
        _;
    }

    function testRevertsIfAmountToBurnIsLessThanBalance() public mintDSC {
        vm.prank(address(engine));
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStaleCoin__BurnAmountExceedBalance.selector);
        dsc.burn(12 ether);
    }

    function testBurnDSC() public mintDSC {
        vm.prank(address(engine));
        dsc.burn(10 ether);
    }
}
