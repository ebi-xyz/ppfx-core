#!/bin/zsh
HEX_REGEX='^[0-9a-fA-F]+$'
# configs
source .env

COMMIT=$(git rev-parse HEAD)
echo "Upgrading contract with commit:\n    $COMMIT"

TESTNET=$1
ACCOUNT=$2

EBI_MAINNET_VERIFY_URL="https://explorer.ebi.xyz/api\?"
EBI_TESTNET_VERIFY_URL="https://explorer.figarolabs.dev/api\?"

RPC=$(if [ "$TESTNET" = true ]; then echo "$EBI_TESTNET_RPC"; else echo "$EBI_MAINNET_RPC"; fi)
VERIFY_URL=$(if [ "$TESTNET" = true ]; then echo "$EBI_TESTNET_VERIFY_URL"; else echo "$EBI_MAINNET_VERIFY_URL"; fi)

echo "Deploy configs: "
echo "    Testnet=$TESTNET"
echo "    RPC=$RPC"
echo "    PPFX=$PPFX"

echo "PPFX configs: "
echo "    ADMIN=$ADMIN\n    INSURANCE=$INSURANCE\n    TREASURY=$TREASURY\n    USDT=$USDT"
echo "    MIN_ORDER_AMT=$MIN_ORDER_AMT\n    WITHDRAW_WAIT_TIME=$WITHDRAW_WAIT_TIME"
echo "Upgrading PPFX...."


if [[ $ACCOUNT =~ $HEX_REGEX ]]; then
    echo "Using Private key to deploy"
    forge clean && forge script script/PPFXUpgrade.s.sol:PPFXProxyUpgradeScript --broadcast --verify --verifier blockscout --verifier-url $VERIFY_URL --rpc-url $RPC --private-key $ACCOUNT --gas-estimate-multiplier 2500 --optimize --optimizer-runs 200
else    
    echo "Using Account: $ACCOUNT to deploy"
    forge clean && forge script script/PPFXUpgrade.s.sol:PPFXProxyUpgradeScript --broadcast --verify --verifier blockscout --verifier-url $VERIFY_URL --rpc-url $RPC --account $ACCOUNT --gas-estimate-multiplier 2500 --optimize --optimizer-runs 200
fi

