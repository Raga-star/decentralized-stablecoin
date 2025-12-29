# Decentralized Stablecoin (DSC) Protocol

A minimal, algorithmic stablecoin protocol designed to maintain a 1:1 peg with the US Dollar, backed by exogenous collateral (WETH and WBTC).

## Overview

The DSC protocol is similar to DAI but with key differences:
- **No governance** - Fully algorithmic and decentralized
- **No fees** - Zero protocol fees for minting, burning, or liquidations
- **Exogenous collateral only** - Backed exclusively by WETH and WBTC
- **Overcollateralized** - Requires 200% collateralization ratio

## Core Components

### 1. DSCEngine.sol
The main contract that handles all protocol logic:
- Collateral deposits and withdrawals
- DSC minting and burning
- Liquidation mechanics
- Health factor calculations

### 2. DecentralizedStableCoin.sol
The ERC20 stablecoin token itself, implementing:
- Minting (only by DSCEngine)
- Burning
- Standard ERC20 functionality

### 3. OracleLib.sol
A library for safe Chainlink oracle interactions:
- Checks for stale price data
- Reverts if oracle data is older than 3 hours
- Protects against using invalid pricing

## Key Features

### Collateral Management
- **Supported collateral**: WETH (Wrapped Ethereum) and WBTC (Wrapped Bitcoin)
- **Deposit collateral**: Lock tokens to back your DSC
- **Withdraw collateral**: Retrieve tokens while maintaining health factor
- **Combined operations**: Deposit and mint in one transaction

### Minting & Burning
- **Mint DSC**: Create new DSC tokens against your collateral
- **Burn DSC**: Destroy DSC to free up collateral
- **Health factor enforcement**: All operations check collateralization

### Liquidation System
- **Liquidation threshold**: 200% overcollateralization required
- **Liquidation bonus**: 10% reward for liquidators
- **Partial liquidations**: Can liquidate portions of undercollateralized positions
- **Automated safety**: Protects protocol from insolvency

## Health Factor

The health factor determines if a position is safe:

```
Health Factor = (Collateral Value × Liquidation Threshold) / DSC Minted
```

- **Health Factor ≥ 1**: Position is safe
- **Health Factor < 1**: Position can be liquidated
- **Minimum required**: 1.0 (1e18 in contract)

### Example Calculation
- User deposits $200 worth of ETH
- User mints 100 DSC
- Collateral adjusted for threshold: $200 × 50% = $100
- Health Factor: $100 / $100 = 1.0 ✓

If ETH price drops and collateral value becomes $180:
- Collateral adjusted: $180 × 50% = $90
- Health Factor: $90 / $100 = 0.9 ❌ (Liquidatable)

## Protocol Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `LIQUIDATION_THRESHOLD` | 50% | Minimum collateral ratio (200% overcollateralized) |
| `LIQUIDATION_BONUS` | 10% | Reward for liquidators |
| `MIN_HEALTH_FACTOR` | 1e18 | Minimum safe health factor |
| `PRECISION` | 1e18 | Calculation precision |

## Main Functions

### User Operations

#### depositCollateral
```solidity
function depositCollateral(
    address tokenCollateralAddress,
    uint256 amountCollateral
) public
```
Deposit WETH or WBTC as collateral.

#### mintDsc
```solidity
function mintDsc(uint256 amountDscToMint) public
```
Mint DSC tokens against your collateral.

#### depositCollateralAndMintDsc
```solidity
function depositCollateralAndMintDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToMint
) external
```
Combine deposit and mint in one transaction.

#### redeemCollateral
```solidity
function redeemCollateral(
    address tokenCollateralAddress,
    uint256 amountCollateral
) public
```
Withdraw collateral (must maintain health factor).

#### burnDsc
```solidity
function burnDsc(uint256 amount) public
```
Burn DSC to reduce debt.

#### redeemCollateralForDsc
```solidity
function redeemCollateralForDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToBurn
) external
```
Burn DSC and withdraw collateral in one transaction.

### Liquidation

#### liquidate
```solidity
function liquidate(
    address collateral,
    address user,
    uint256 debtToCover
) external
```
Liquidate an undercollateralized position:
- Burns liquidator's DSC to cover user's debt
- Transfers user's collateral to liquidator
- Includes 10% bonus as incentive
- User's health factor must improve

## View Functions

```solidity
// Get account information
function getAccountInformation(address user) 
    external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd)

// Get USD value of tokens
function getUsdValue(address token, uint256 amount) 
    public view returns (uint256)

// Get token amount from USD value
function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) 
    public view returns (uint256)

// Get user's collateral balance
function getCollateralBalanceOfUser(address user, address token) 
    external view returns (uint256)

// Get protocol constants
function getMinHealthFactor() external pure returns (uint256)
function getLiquidationThreshold() external pure returns (uint256)
function getLiquidationBonus() external pure returns (uint256)
```

## Security Features

### Reentrancy Protection
All state-changing functions use OpenZeppelin's `ReentrancyGuard`.

### Checks-Effects-Interactions Pattern
Functions follow the CEI pattern to prevent reentrancy and ensure state consistency.

### Oracle Safety
- Uses Chainlink price feeds for real-time pricing
- Implements `OracleLib` to check for stale data
- Reverts if price data is older than 3 hours

### Health Factor Enforcement
Every operation that could affect collateralization is checked:
- Deposits check health factor
- Mints check health factor
- Withdrawals check health factor
- Liquidations verify improvement

## Testing

The protocol includes comprehensive testing:

### Handler Contract
Located in `test/fuzz/Handler.sol`, it simulates:
- Random deposits and withdrawals
- Minting and burning operations
- Price fluctuations (via `updateEthPrice`, `updateBtcPrice`)
- Market crashes (via `crashCollateralPrices`)
- Liquidation scenarios

### Invariants Tested
1. Protocol must remain overcollateralized
2. Total DSC minted ≤ Total collateral value
3. Users cannot be liquidated if health factor ≥ 1
4. Liquidations must improve user's health factor

## Known Limitations

1. **Oracle Dependency**: If Chainlink fails, the protocol becomes unusable by design
2. **Liquidation Incentives**: Protocol assumes sufficient overcollateralization - if severely undercollateralized, liquidators may not be incentivized
3. **Two Collateral Types Only**: Currently limited to WETH and WBTC
4. **No Governance**: Cannot be upgraded or modified without redeployment

## Deployment

```solidity
constructor(
    address[] memory tokenAddresses,      // [WETH, WBTC]
    address[] memory priceFeedAddresses,  // [ETH/USD, BTC/USD]
    address dscAddress                    // DSC token address
)
```

## Usage Example

```solidity
// 1. Deposit 1 ETH as collateral
weth.approve(address(dscEngine), 1 ether);
dscEngine.depositCollateral(address(weth), 1 ether);

// 2. Mint 1000 DSC (assuming ETH = $2000, you have $2000 collateral)
// With 200% overcollateralization, you can mint up to $1000 worth
dscEngine.mintDsc(1000 ether);

// 3. Later, burn DSC and withdraw
dsc.approve(address(dscEngine), 1000 ether);
dscEngine.redeemCollateralForDsc(address(weth), 0.5 ether, 1000 ether);
```

## Emergency Scenarios

### Market Crash
1. Collateral prices drop significantly
2. Users' health factors fall below 1.0
3. Liquidators burn DSC to cover debt
4. Liquidators receive collateral + 10% bonus
5. Protocol returns to overcollateralized state

### Oracle Failure
1. Chainlink price feed becomes stale (>3 hours)
2. All price-dependent operations revert
3. Users cannot deposit, mint, or redeem
4. System freezes until oracle recovers
5. This is intentional to prevent using invalid prices

## License

MIT

## Author

nifemi

## Acknowledgments

Loosely based on MakerDAO's DSS (DAI Stablecoin System)