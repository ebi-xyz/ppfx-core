#!/bin/zsh
HEX_REGEX='^[0-9a-fA-F]+$'

source .env

TESTNET=$1
ACCOUNT=$2

RPC=$(if [ "$TESTNET" = true ]; then echo "$EBI_TESTNET_RPC"; else echo "$EBI_MAINNET_RPC"; fi)

echo "Script configs: "
echo "    Testnet=$TESTNET"
echo "    RPC=$RPC"

echo "PPFX configs:"
echo "    PPFX=$PPFX"

echo "Markets:"
echo "    $MARKETS"

echo "Operators:"
echo "    $OPERATORS"

if [[ $ACCOUNT =~ $HEX_REGEX ]]; then
    echo "Using Private key to deploy"
    forge script script/PPFXSetup.s.sol:PPFXSetupScript --broadcast --rpc-url $RPC --private-key $ACCOUNT --gas-estimate-multiplier 2000 --optimize --optimizer-runs 200
else    
    echo "Using Account: $ACCOUNT to deploy"
    forge script script/PPFXSetup.s.sol:PPFXSetupScript --broadcast --rpc-url $RPC --account $ACCOUNT --gas-estimate-multiplier 2000 --optimize --optimizer-runs 200
fi

echo "Done Setup"

echo "> cast call $PPFX 'getAllOperators()(address[])' --rpc-url $RPC"
cast call $PPFX "getAllOperators()(address[])" --rpc-url $RPC

echo "> cast call $PPFX 'getAllMarkets()(bytes32[])' --rpc-url $RPC"
cast call $PPFX "getAllMarkets()(bytes32[])" --rpc-url $RPC
