// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";

contract DeployDSCTest is Test {
    DeployDSC deployer;

    function setUp() public {
        deployer = new DeployDSC();
    }

    function testDeployRunFunction() public {
        deployer.run();
    }
}
