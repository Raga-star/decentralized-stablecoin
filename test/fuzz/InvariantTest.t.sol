// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();

        // Unpack in correct order: wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        console.log("=== Setup Configuration ===");
        console.log("DSC:", address(dsc));
        console.log("DSCEngine:", address(dsce));
        console.log("WETH:", weth);
        console.log("WBTC:", wbtc);
        console.log("WETH Price Feed:", wethUsdPriceFeed);
        console.log("WBTC Price Feed:", wbtcUsdPriceFeed);

        require(weth != address(0), "WETH address cannot be zero");
        require(wbtc != address(0), "WBTC address cannot be zero");
        require(wethUsdPriceFeed != address(0), "WETH price feed cannot be zero");
        require(wbtcUsdPriceFeed != address(0), "WBTC price feed cannot be zero");

        // ✅ Pass all 6 parameters
        handler = new Handler(dsce, dsc, weth, wbtc, wethUsdPriceFeed, wbtcUsdPriceFeed);
        console.log("Handler address:", address(handler));

        targetContract(address(handler));

        console.log("=== Setup Complete ===");
    }

    function invariant_protocolMustHaveMoreCollateralValueThanTotalSupply() public view {
        // Get total DSC supply
        uint256 totalSupply = dsc.totalSupply();

        // Get total collateral deposited in the protocol
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        // Get USD value of collateral
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
        uint256 totalCollateralValueInUsd = wethValue + wbtcValue;

        console.log("=== Invariant Check ===");
        console.log("Total DSC Supply:", totalSupply);
        console.log("WETH Deposited:", totalWethDeposited);
        console.log("WBTC Deposited:", totalWbtcDeposited);
        console.log("WETH Value (USD):", wethValue);
        console.log("WBTC Value (USD):", wbtcValue);
        console.log("Total Collateral Value (USD):", totalCollateralValueInUsd);
        console.log("Times deposit called:", handler.timesDepositIsCalled());
        console.log("Times mint called:", handler.timesMintIsCalled());

        // The protocol must always be overcollateralized
        // Total collateral value should be >= total DSC minted
        assert(totalCollateralValueInUsd >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        // Test that getter functions never revert
        dsce.getAccountCollateralValue(address(this));
        dsce.getAccountInformation(address(this));
    }
}
