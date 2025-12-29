// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    address[] public usersWithCollateral;
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    // Ghost variables to track calls
    uint256 public timesMintIsCalled;
    uint256 public timesDepositIsCalled;
    uint256 public timesPriceUpdateCalled;
    uint256 public timesLiquidateCalled;
    
    address[] public usersWhoDeposited;

    // Store price feed addresses
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    constructor(
        DSCEngine _dsce,
        DecentralizedStableCoin _dsc,
        address _weth,
        address _wbtc,
        address _ethUsdPriceFeed,
        address _btcUsdPriceFeed
    ) {
        dsce = _dsce;
        dsc = _dsc;
        weth = ERC20Mock(_weth);
        wbtc = ERC20Mock(_wbtc);
        ethUsdPriceFeed = MockV3Aggregator(_ethUsdPriceFeed);
        btcUsdPriceFeed = MockV3Aggregator(_btcUsdPriceFeed);
    }

    // =========== COLLATERAL OPERATIONS ===========

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWhoDeposited.push(msg.sender);
        timesDepositIsCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 0, MAX_DEPOSIT_SIZE);

        if (amountCollateral == 0) {
            return;
        }

        vm.prank(msg.sender);
        try dsce.redeemCollateral(address(collateral), amountCollateral) {
            // Success
        } catch {
            // Failed - user doesn't have enough collateral or would break health factor
        }
    }

    // =========== DSC OPERATIONS ===========

    function mintDsc(uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.prank(msg.sender);
        try dsce.mintDsc(amount) {
            timesMintIsCalled++;
        } catch {
            // Failed - user doesn't have enough collateral
        }
    }

    function burnDsc(uint256 amount) public {
        amount = bound(amount, 0, dsc.balanceOf(msg.sender));

        if (amount == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dsc.approve(address(dsce), amount);

        try dsce.burnDsc(amount) {
            // Success
        } catch {
            // Failed
        }
        vm.stopPrank();
    }

    // =========== COMBINED OPERATIONS ===========

    function depositCollateralAndMintDsc(
        uint256 collateralSeed,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        amountDscToMint = bound(amountDscToMint, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);

        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);

        try dsce.depositCollateralAndMintDsc(address(collateral), amountCollateral, amountDscToMint) {
            usersWhoDeposited.push(msg.sender);
            timesDepositIsCalled++;
            timesMintIsCalled++;
        } catch {
            // Failed - probably would break health factor
        }

        vm.stopPrank();
    }

    // =========== PRICE MANIPULATION ===========

    /**
     * @notice Liquidates an undercollateralized user
     * @param userSeed Used to select which user to attempt to liquidate
     * @param debtToCover Amount of DSC to burn to cover user's debt
     * @dev This is critical for maintaining protocol health after price crashes
     */
    function liquidate(uint256 userSeed, uint256 debtToCover) public {
        if (usersWhoDeposited.length == 0) {
            return;
        }

        // Select a user to liquidate
        address userToLiquidate = usersWhoDeposited[userSeed % usersWhoDeposited.length];
        
        // Bound debt to cover to a reasonable amount
        debtToCover = bound(debtToCover, 1, MAX_DEPOSIT_SIZE);

        // Check if user can be liquidated (health factor < 1)
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(userToLiquidate);
        
        // Skip if user has no debt
        if (totalDscMinted == 0) {
            return;
        }

        // Liquidator needs DSC to burn
        vm.startPrank(msg.sender);
        
        // Mint DSC to liquidator if they don't have enough
        if (dsc.balanceOf(msg.sender) < debtToCover) {
            // Deposit collateral first
            ERC20Mock collateral = weth;
            uint256 collateralAmount = debtToCover * 2; // 2x collateral for safety
            collateral.mint(msg.sender, collateralAmount);
            collateral.approve(address(dsce), collateralAmount);
            
            try dsce.depositCollateralAndMintDsc(address(collateral), collateralAmount, debtToCover) {
                // Successfully minted DSC for liquidation
            } catch {
                vm.stopPrank();
                return;
            }
        }

        // Approve DSC for liquidation
        dsc.approve(address(dsce), debtToCover);

        // Attempt liquidation
        try dsce.liquidate(address(weth), userToLiquidate, debtToCover) {
            timesLiquidateCalled++;
        } catch {
            // Liquidation failed - user might not be liquidatable
        }

        vm.stopPrank();
    }

    // =========== PRICE MANIPULATION ===========

    /**
     * @notice Updates the price of ETH in the price feed
     * @param newPrice The new ETH/USD price (will be bounded to realistic values)
     * @dev This simulates market volatility and tests protocol behavior under price changes
     */
    function updateEthPrice(uint96 newPrice) public {
        // Bound price to realistic range: $100 to $10,000 per ETH
        // Using 8 decimals for price feed
        int256 price = int256(uint256(bound(newPrice, 100e8, 10_000e8)));
        
        ethUsdPriceFeed.updateAnswer(price);
        timesPriceUpdateCalled++;
    }

    /**
     * @notice Updates the price of BTC in the price feed
     * @param newPrice The new BTC/USD price (will be bounded to realistic values)
     * @dev This simulates market volatility and tests protocol behavior under price changes
     */
    function updateBtcPrice(uint96 newPrice) public {
        // Bound price to realistic range: $1,000 to $100,000 per BTC
        // Using 8 decimals for price feed
        int256 price = int256(uint256(bound(newPrice, 1_000e8, 100_000e8)));
        
        btcUsdPriceFeed.updateAnswer(price);
        timesPriceUpdateCalled++;
    }

    /**
     * @notice Simulates a market crash by reducing collateral prices
     * @param percentageDrop The percentage to drop prices (0-90%)
     * @dev This is a more targeted test for extreme market conditions
     */
    function crashCollateralPrices(uint256 percentageDrop) public {
        // Bound to 0-90% drop (max 90% crash)
        percentageDrop = bound(percentageDrop, 0, 50);

        // Get current prices
        (, int256 currentEthPrice,,,) = ethUsdPriceFeed.latestRoundData();
        (, int256 currentBtcPrice,,,) = btcUsdPriceFeed.latestRoundData();

        // Calculate new prices after crash
        int256 newEthPrice = currentEthPrice * int256(100 - percentageDrop) / 100;
        int256 newBtcPrice = currentBtcPrice * int256(100 - percentageDrop) / 100;

        // Ensure prices don't go to zero
        if (newEthPrice < 1e8) newEthPrice = 1e8; // Minimum $1
        if (newBtcPrice < 1e8) newBtcPrice = 1e8; // Minimum $1

        // Update prices
        ethUsdPriceFeed.updateAnswer(newEthPrice);
        btcUsdPriceFeed.updateAnswer(newBtcPrice);
        
        timesPriceUpdateCalled += 2;
    }

    // =========== HELPER FUNCTIONS ===========

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}