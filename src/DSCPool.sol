// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSC Pool
 * @author Samuel Muto
 * @notice This contract collects remaining funds from a liquidated user.
 */
contract DSCPool {
    ///////////
    // Error //
    ///////////
    error DSCPool__NotOwner();
    error DSCPool__DoesNotHaveTheAmount();
    error DSCPool__TransferFailed();

    ////////////
    // Events //
    ////////////
    event Received(address, uint256);

    /////////////////////
    // State variables //
    /////////////////////
    address private immutable i_owner;

    //////////////
    // Modifier //
    //////////////

    modifier onlyOwner() {
        if (msg.sender != i_owner) {
            revert DSCPool__NotOwner();
        }
        _;
    }

    modifier poolHasBalance(uint256 amount) {
        if (amount > address(this).balance) {
            revert DSCPool__DoesNotHaveTheAmount();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////
    constructor() {
        i_owner = msg.sender;
    }

    function withdraw(address collateral, uint256 amount) external onlyOwner poolHasBalance(amount) {
        bool success = IERC20(collateral).transfer(msg.sender, amount);
        if (!success) {
            revert DSCPool__TransferFailed();
        }
    }

    function getBalance(address collateral) external view returns (uint256) {
        return IERC20(collateral).balanceOf(address(this));
    }
}
