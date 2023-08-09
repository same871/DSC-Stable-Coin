// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Samuel Muto
 * @notice This library is used to check the Chainlink Oracle for stale date.
 * If a price is stale, the function will revert, and render the DSCEngine unusable. This is by design
 * We wan the DSCEngine to freeze if the prices became stale
 *
 * So if the chainlink network explodes and you have a lot of money locked in the protocol... too bad
 *
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function stalePriceCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSInce = block.timestamp - updatedAt;
        if (secondsSInce > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
