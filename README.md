# PPFX

This repository contains the core contract for PPFX, a fast and non-custodial perp DEX.
- All settlement in single currency, e.g. USDT. 
- Supports isolated margin
- Users may deposit or withdraw funds at any time. Funds that are not collateralized for positions can be withdrawn via 2-step withdrawal process. 
- Funding rates are settled every 8 hours. 

## Docs

See [Docs](DOCS.md) for product specs explaining the functions of the contracts.

## Setup

PPFX is built with [Foundry](https://book.getfoundry.sh/). 

```shell
# build
$ forge build

# test
$ forge test

# lint/formatter
$ forge fmt

# gas snapshot
$ forge snapshot

# deploy
$ forge script script/PPFX.s.sol:PPFXScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Overview

PPFX defines a few roles: 
- `Users` may deposit and withdraw funds. 
- `Operator` modifies user balances when user positions are added or reduced, and settles all funding rate payments. The `Operator` may not directly update user balances or withdraw any funds. 
- `Admin` may update `operator` and `treasury` addresses. 
- `Treasury` and `Insurance` are defined recipients for fees but otherwise don't have any privileges.


### User Balances

Users have `funding` balance and `trading` balances. 
- When a user deposits or withdraws funds, it is to and from their `funding` balance
- When a user places an order, funds are moved from their `funding` balance to their `trading` balance, where it is held as collateral for their posiiton. When they reduce or close the position, funds are moved from their `trading` balance to their `funding` balance. 

Users may only have 1 position per market (they are either long or short). Their position is backed by their collateral stored as `trading` balances. 
- Each user position is backed by funds  `(user, market)` pair, e.g. `(user_123, btc)`. 
- Only the `operator` may manage user `trading` balances. 


### User Functions

PPFX assumes a single unit of currency, which is defined as `USDT`. Funds are withdrawn by first calling `withdraw`, and then after some blocks calling `claim`. 
- `function deposit(uint256 amount) external` 
- `function withdraw(uint256 amount) external`

If `user` has a pending withdraw, they may claim funds after a pre-determined number of blocks. 
- `function claimPendingWithdrawal() external`

### Operator Functions

When users place new orders, add, or reduce their positions, the `operator` then calls smart contract to manage user `trading` balances. 
- `function addPosition(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator`
- `function reducePosition(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator`
- `function fillOrder(address user, string memory marketName, uint256 fee) external onlyOperator`
- `function cancelOrder(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator`

**Important** 
Adding position is called by `operator` when user places an order, but is not yet filled. `addPosition` and `reducePosition` are not symmetrical!
- When user places an order, to add to or create a new position, we should update `trading` balance immediately to avoid users from being under-collateralized. 
- Once the order is filled, the collateral is already held in `trading` balance, so we only handle fees by calling `fillOrder`. 
- If user cancels order before it is filled, the collateral held in `trading` balance is then released back to `funding`. 
- When user places an order to reduce an existing position, we wait until the order is filled to update `trading` balance and handle fees. 

Users may add or reduce collateral from existing positions. 
- `function addCollateral(address user, string memory marketName, uint256 amount) external onlyOperator`
- `function reduceCollateral(address user, string memory marketName, uint256 amount) external onlyOperator`

Operator may settle funding rate fees for each user position. 
- `function settleFundingFee(address user, string memory marketName, uint256 amount) external onlyOperator`

Operator may process user liquidations
- `function liquidate(address user, string memory marketName, uint256 amount, uint256 fee) external onlyOperator`





