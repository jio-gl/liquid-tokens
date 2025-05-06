# A Library and Hub for Price-stable and more liquid ERC20 Smart Contract Tokens written in Solidity.

## Main design goals:

* Use token supply rebasement to estabilize price a little and give or remove liquidity when is needed.
* Use token activity, or other on-chain metrics to estimate changes on value.
* Use lazy update of each wallet balance, when each wallet address owner desires.
* Use ETH collateral to bootstrap the token.
* Include a Pump&Dump protection through rebasement limits.

## Project goals:

* Implement LiquidToken, a liquid token measuring activity, i.e. number of transactions per period (example period is daily).
* Implement DifficultyToken, a liquid token tracking an on-chain floating metric that is block difficulty: one token per difficulty unit.
* Implement a Hub so each organization can implement their own liquid token setting some parameters.

Work in progress.. :D

# Liquid Token

A modern ERC20 token implementation with dynamic burn and mint rates based on transaction volume, designed to be friendly with centralized exchanges.

## Features

- **Dynamic Burn Rate**: Burns a small percentage of tokens on transfers based on transaction volume and supply
- **Transaction-Based Rebasement**: Uses number of transactions to determine the daily rebasement ratio
- **Moving Average Metrics**: Calculates token rebasement using a moving average of transaction activity
- **CEX-Friendly**: Maintains an effective balance vs displayed balance to be compatible with exchanges
- **Two-Phase System**: Initially inflationary to incentivize early adoption, then transitions to a deflationary model
- **Pump & Dump Protection**: Includes limits on rebasement to make currency manipulation economically unfeasible

## Technical Details

- **Initial Inflationary Period**: Users can mint tokens for free and new holders get airdrops
- **Deflationary Period**: After 75% of the cap is reached, transitions to a controlled deflationary model
- **Dynamic Rate Calculation**: Burn rate increases with higher transaction activity compared to the moving average
- **Annual Targets**: Each year sets a new target supply based on the annual burn rate (default 4%)
- **View vs Non-View Balance**: Displays projected balance including potential mints in view functions
- **Early Adopters Premium**: Gradually declining bootstrap premium to encourage early participation

## Transaction-Based Rate Calculation

The rebasement ratio is calculated using:
1. **Transaction Volume Metrics**: Compares current period transactions to a moving average
2. **Dynamic Burn Rate**: Increases with transaction activity, capped for economic stability
3. **Early Adopters Premium**: Decays over time as the token matures
4. **Target Supply Tracking**: Adjusts based on how far current supply is from target

## Project Structure

```
liquid-tokens/
├── contracts/              # Smart contracts
│   └── LiquidToken.sol     # Main token implementation
├── scripts/                # Deployment scripts
│   └── deploy.js           # Script for deploying the token
├── test/                   # Tests
│   ├── LiquidToken.test.js # Basic token tests
│   └── DynamicRates.test.js # Tests for dynamic rate calculations
├── hardhat.config.js       # Hardhat configuration
└── package.json            # Project dependencies
```

## Getting Started

### Prerequisites

- Node.js (v16+)
- npm or yarn

### Installation

```bash
# Install dependencies
npm install
```

### Compiling

```bash
# Compile contracts
npm run compile
```

### Testing

```bash
# Run tests
npm test
```

### Deployment

```bash
# Deploy to local network
npm run deploy:local

# Start local blockchain node
npm run node
```

## Contract Interaction

### Key Functions

- `mint()`: Mint tokens during the inflationary period
- `transfer(address to, uint256 amount)`: Transfer tokens with automatic burn applied
- `balanceOf(address account)`: View function showing balance including projected mints
- `effectiveBalanceOf(address account)`: View function showing actual balance without projections
- `rebase()`: Update the token's metrics and rates (automatically triggered daily)
- `getCurrentPeriodTxCount()`: View the current period's transaction count
- `getMovingAverageTxCount()`: View the moving average transaction count

## License

This project is licensed under the MIT License.