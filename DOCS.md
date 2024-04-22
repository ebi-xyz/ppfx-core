# PPFX Docs

# Overview
The PPFX smart contracts will store user deposits and maintain collateral and funding balance. 
- `Users` may deposit and withdraw from their wallets into and out of the smart contract. 
- The `operator` calculates the collateral allocated to each user, and in turn instructs the smart contracts on the amount they can withdraw back to their wallets.

## Trading balance
The balance that is used in isolated (or cross, in the future) margin to support the users positions. 

Trading balance =
Margin locked in isolated positions
+ (Cross margin position size+order size)/max leverage tier 
- [all funding payments paid out]

It may be updated when:
- User places an order, which includes:
    + A new position
    + Adding to an open position
    + Reducing an open position
    + Closing a position
- User cancels an order. This is the reverse of the above. 
- User pays funding rate for open positions

Unrealized P&L is not reflected on trading balance in smart contract outside of the 8 hour update

## Deposit funds
As a user I want to deposit funds to my funding balance. 
- Allow users to deposit USDT only
- Total Balance += deposit amount
- Funding balance += deposit amount
- Post an on-chain event for the user_id and deposit amount. 


## Withdraw funds
As a user I want to withdraw from my funding balance. Since user orders and positions are off-chain, there could be a race condition when users try to withdraw funds. We address this with 2-step process:
- Start withdraw
    + Allow users to start withdrawal of USDT from user funding balance. 
    + Withdraw amount should be less than the user funding balance
    + Funding Balance -= withdraw amount
    + Pending withdrawal balance += withdraw amount
- Claim funds
    + Allow users to claim pending withdraw balance
    + Should be N time (or N blocks) since the withdrawal transaction. 
    + Pending Balance should be set to 0


# Operator Actions

Unless specified, orders apply to both longs and shorts. 

## Open Order
As Operator, we want to lock up user collateral when users open orders. This is governed by the size of the trade, and the Initial Margin required for that market and size. When an order is placed, Operator should move an amount and fee from the User Funding Balance to User Trading Balance for (user, market) tuple. 
- Specify (user, market, amount, fee)
- User funding balance -= amount + fee
- User trading balance += amount + fee
    + If trading balance is 0 or does not exist, then it is = amount + fee
- Amount + Fee should be less than User funding balance

Note: The amount is determined by `Initial Margin * Position size * Limit price + fees`

This is managed by the Backend system; As Operator we should only specify to contract the (amount, fee). 

## Cancel Order
As Operator, we want to release user collateral when users cancel orders. 
- Specify (user, market, amount, fee)
- User funding balance += amount + fee
- User trading balance -= amount + fee
- Amount + Fee should be less than User trading balance

Note: The amount is determined by Amount to move = `Initial Margin * Position size + fees`

This is managed by the Backend system; As Operator we should only specify to contract the (amount, fee). 

## Fill Order (Pay Fee)
As Operator, we want to collect fees from users when orders opening new positions, either Long order or Short order, are filled. 
- Treasury += fee
- User trading balance -= fee
- Fee should be less than user trading balance
- User funding balance is NOT changed since they were previously updated when opening an order. 

## Add Order
As Operator, we want to lockup collateral when a user places orders to add to an existing position.  Adding to an existing position follows the same logic as Open Order. 
- Specify (user, market, amount, fee)
- User funding balance -= amount + fee
- User trading balance += amount + fee
- Amount + Fee should be less than User funding balance

## Reduce Position
As Operator, we want to release collateral after a user places an order to reduce their position, and it is filled. In this case the fee is paid from the trading balance. 
- Specify (user, market, amount, uPNL, isProfit, fee)
- If isProfit = true
    + User funding balance += amount + uPNL
    + User trading balance -= amount - fee
- If isProfit = false
    + User funding balance += amount - uPNL
    + User trading balance -= amount - fee
    + The uPNL should be less than the user trading balance
- Treasury += fee
- The Amount should be less than the user trading balance. 

## Close Position (ie reduce 100% of position)
Closing a position follows the same logic as Reduce Position where Amount = Trading Balance.  
- Specify (user, market, uPNL, isProfit, fee)
- If isProfit = true
    + User funding balance += tradingBalance + uPNL - fee
    + User trading balance = 0
- If isProfit = false
    + User funding balance += tradingBalance - uPNL - fee
    + User trading balance = 0 
    + The uPNL should be less than tradingBalance, minus fee. 
- Treasury += fee
- The Amount should be less than the user trading balance. 

## Settle Funding Fees
As Operator I want to update the users trading and funding balance at funding rate settlement. 
- Allow Operator to add funding amount to user funding balance. 
- Allow Operator to deduct funding amount from user trading balance for each (user, market, amount). 

## Liquidation
As operator I want to collect liquidation fees from users when liquidation happens while closing 100% of the position
- Specify (user_id, market, amount, fee)
- (User position of the market = 0)
- User trading balance = 0
- User funding balance +=amount
- Insurance account += fee

## Add Collateral
As Operator I want to update users' trading balance when users choose to add collateral within a position (mainly to prevent liquidation). 
- Specify (user_id, market, amount)
- User funding balance += amount
- User trading balance -= amount
- Amount should be less than trading balance
- No fees are charged for users adjust collateral

## Reduce Collateral
As Operator I want to update users' trading balance when users choose to reduce collateral within a position, and increase their margin. 
- Specify (user_id, market, amount)
- User funding balance -=amount
- User trading balance += amount
- Amount should be less than funding balance
- No fees are charged
