// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralisedStableCoin
 * @author Samuel Muto
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * @notice This contract is meant to be governed by DSCEngine. This contract is justthe ERC20 implementation of our stablecoin system.
 */
contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    ////////////
    // ERRORS //
    ////////////

    error DecentralisedStaleCoin__MustBeMoreThanZero();
    error DecentralisedStaleCoin__BurnAmountExceedBalance();
    error DecentralisedStableCoin__NotZeroAddress();

    //////////////////////////////
    // FUNCTIONS                //
    //////////////////////////////

    constructor() ERC20("DecentralisedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStaleCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralisedStaleCoin__BurnAmountExceedBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStaleCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
