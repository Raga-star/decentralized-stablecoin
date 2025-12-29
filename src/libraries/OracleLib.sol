// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Nifemi
 * @notice this library is used to check the Chainlink oracle for stale data.
 * if a price is stale function will revert, and render the DSCEngine unusable - this is by design.
 *
 * so if the chainlink network explodes and you have a lot of positions open, you will not be able to
 * add more collateral or open new positions until the oracle is back online.
 */
library OracleLib {
    error oracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface pricefeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundID, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            pricefeed.latestRoundData();

        uint256 secondSince = block.timestamp - updatedAt;
        if (secondSince > TIMEOUT) {
            revert oracleLib__StalePrice();
        }
        return (roundID, answer, startedAt, updatedAt, answeredInRound);
    }
}
