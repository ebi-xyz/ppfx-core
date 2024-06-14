#!/bin/zsh
HEX_REGEX='^[0-9a-fA-F]+$'

COMMIT=$(git rev-parse HEAD)
echo "Deploying PPFX with commit:\n    $COMMIT"

ACCOUNT=$1

### Load Config ###
DEPLOY_CONFIG=$(cat config/deployConfig.json | jq)
TESTNET=$(echo "$DEPLOY_CONFIG" | jq -r '.IsMainnet')
EBI_TESTNET_RPC=$(echo "$DEPLOY_CONFIG" | jq -r '.EbiTestnetRPC')
EBI_MAINNET_RPC=$(echo "$DEPLOY_CONFIG" | jq -r '.EbiMainnetRPC')
EBI_MAINNET_VERIFY_URL="https://explorer.ebi.xyz/api\?",
EBI_TESTNET_VERIFY_URL="https://explorer.figarolabs.dev/api\?"

RPC=$(if [ "$TESTNET" = true ]; then echo "$EBI_TESTNET_RPC"; else echo "$EBI_MAINNET_RPC"; fi)
VERIFY_URL=$(if [ "$TESTNET" = true ]; then echo "$EBI_TESTNET_VERIFY_URL"; else echo "$EBI_MAINNET_VERIFY_URL"; fi)

CONFIG=$(cat config/ppfxConfig.json | jq)
STR_CONFIG=$(cat config/ppfxStrConfig.json | jq)

ADMIN=$(echo "$CONFIG" | jq -r '.admin')
INSURANCE=$(echo "$CONFIG" | jq -r '.insurance')
TREASURY=$(echo "$CONFIG" | jq -r '.treasury')
USDT=$(echo "$CONFIG" | jq -r '.usdt')
MIN_ORDER_AMT=$(echo "$CONFIG" | jq -r '.minOrderAmount')
WITHDRAW_WAIT_TIME=$(echo "$CONFIG" | jq -r '.withdrawWaitTime')
PPFX_VERSION=$(echo "$STR_CONFIG" | jq -r '.ppfxVersion')

echo "Deploy configs: "
echo "    Testnet=$TESTNET"
echo "    RPC=$RPC"

echo "PPFX configs: "
echo "    PPFX Version=$PPFX_VERSION"
echo "    ADMIN=$ADMIN\n    INSURANCE=$INSURANCE\n    TREASURY=$TREASURY\n    USDT=$USDT"
echo "    MIN_ORDER_AMT=$MIN_ORDER_AMT\n    WITHDRAW_WAIT_TIME=$WITHDRAW_WAIT_TIME"
echo "creating PPFX...."


if [[ $ACCOUNT =~ $HEX_REGEX ]]; then
    echo "Using Private key to deploy"
    forge clean && forge script script/PPFXProxyDeployment.s.sol:PPFXProxyDeploymentScript --broadcast --verify --verifier blockscout --verifier-url $VERIFY_URL --rpc-url $RPC --private-key $ACCOUNT --gas-estimate-multiplier 2000 --optimize --optimizer-runs 200
else    
    echo "Using Account: $ACCOUNT to deploy"
    forge clean && forge script script/PPFXProxyDeployment.s.sol:PPFXProxyDeploymentScript --broadcast --verify --verifier blockscout --verifier-url $VERIFY_URL --rpc-url $RPC --account $ACCOUNT --gas-estimate-multiplier 2000 --optimize --optimizer-runs 200
fi

