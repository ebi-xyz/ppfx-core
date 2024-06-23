#!/bin/zsh
HEX_REGEX='^[0-9a-fA-F]+$'
# configs
source .env

COMMIT=$(git rev-parse HEAD)
echo "Upgrading contract with commit:\n    $COMMIT"

DEPLOY_CONFIG=$(cat config/deployConfig.json | jq)
TESTNET=$(echo "$DEPLOY_CONFIG" | jq -r '.IsTestnet')

ACCOUNT=$1

EBI_TESTNET_RPC=$(echo "$DEPLOY_CONFIG" | jq -r '.EbiTestnetRPC')
EBI_MAINNET_RPC=$(echo "$DEPLOY_CONFIG" | jq -r '.EbiMainnetRPC')
EBI_MAINNET_VERIFY_URL="https://explorer.ebi.xyz/api\?",
EBI_TESTNET_VERIFY_URL="https://explorer.figarolabs.dev/api\?"

RPC=$(if [ "$TESTNET" = true ]; then echo "$EBI_TESTNET_RPC"; else echo "$EBI_MAINNET_RPC"; fi)
VERIFY_URL=$(if [ "$TESTNET" = true ]; then echo "$EBI_TESTNET_VERIFY_URL"; else echo "$EBI_MAINNET_VERIFY_URL"; fi)

PPFX=$(cat config/ppfxUpgradeConfig.json | jq -r '.ppfx')

echo "Deploy configs: "
echo "    Testnet=$TESTNET"
echo "    RPC=$RPC"
echo "    PPFX=$PPFX"
echo "Upgrading PPFX...."


if [[ $ACCOUNT =~ $HEX_REGEX ]]; then
    echo "Using Private key to deploy"
    forge clean && forge script script/PPFXUpgrade.s.sol:PPFXProxyUpgradeScript --broadcast --verify --verifier blockscout --verifier-url $VERIFY_URL --rpc-url $RPC --private-key $ACCOUNT --gas-estimate-multiplier 2500 --optimize --optimizer-runs 200
else    
    echo "Using Account: $ACCOUNT to deploy"
    forge clean && forge script script/PPFXUpgrade.s.sol:PPFXProxyUpgradeScript --broadcast --verify --verifier blockscout --verifier-url $VERIFY_URL --rpc-url $RPC --account $ACCOUNT --gas-estimate-multiplier 2500 --optimize --optimizer-runs 200
fi

