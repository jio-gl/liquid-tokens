A Library and Hub for Price-stable and more liquid ERC20 Smart Contract Tokens written in Solidity.

Main design goals:

1) Use token supply rebasement to estabilize price a little and give or remove liquidity when is needed.
2) Use token activity, or other on-chain metrics to estimate changes on value.
2) Use lazy update of each wallet balance, when the owner desires.
3) Use ETH collateral to bootstrap the token.
4) Include a Pump&Dump protection through rebasement limits.

Project goals:

a) Implement LiquidToken, a liquid token measuring activity, i.e. number of transactions per period (example period is daily).
b) Implement DifficultyToken, a liquid token tracking an on-chain floating metric that is block difficulty: one token per difficulty unit.
c) Implement a Hub so each organization can implement their own liquid token setting some parameters.

Work in progress.. :D

References:

A Stable Coin with Pro-rated Rebasement and Price Manipulation Protection
https://arxiv.org/abs/1708.00157