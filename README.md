
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

## References:

1. A Stable Coin with Pro-rated Rebasement and Price Manipulation Protection
https://arxiv.org/abs/1708.00157