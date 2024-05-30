#!/bin/zsh

# configs
RPC=https://rpc.ebi.xyz
ADMIN=0x7C44e3ab48a8b7b5779BE7fFB06Fec0eB6a41faE
INSURANCE=0x1fA3f3F219ce4C6d8E97d081aDaDBd33899A24Fe
TREASURY=0x16b68c1F569Ffc6D594c43CEFf7dF1116005Bfe4
USDT=0x5489DDAb89609580835eE6d655CD9B3503E7F97D

# min order $0.1
MIN_ORDER_AMT=10000

# withdraw 15mins
WITHDRAW_WAIT_TIME=900

COMMIT=$(git rev-parse HEAD)
echo "deploying contract with commit:\n    $COMMIT"

echo "PPFX configs: "
echo "    ADMIN=$ADMIN\n    INSURANCE=$INSURANCE\n    TREASURY=$TREASURY\n    USDT=$USDT"
echo "    MIN_ORDER_AMT=$MIN_ORDER_AMT\n    WITHDRAW_WAIT_TIME=$WITHDRAW_WAIT_TIME"
echo "creating PPFX...."

forge create src/PPFX.sol:PPFX --constructor-args "$ADMIN" "$TREASURY" "$INSURANCE" "$USDT" "$WITHDRAW_WAIT_TIME" "$MIN_ORDER_AMT"  --rpc-url $RPC --account deployer


