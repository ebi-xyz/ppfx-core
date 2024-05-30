#!/bin/zsh

# configs
RPC=https://rpc.ebi.xyz
PPFX=0x48240679b950b22c47b80B723845161dd6396f7a
echo "PPFX configs:"
echo "    PPFX=$PPFX"

MARKETS=(BTC-USDT ETH-USDT SOL-USDT NEAR-USDT DOGE-USDT TON-USDT WIF-USDT BODEN-USDT RNDR-USDT EIGEN-USDT)
echo "markets:"
echo "    $MARKETS"

# for mkt ($MARKETS)
# do
# cast send $PPFX "addMarket(string)()" $mkt --rpc-url $RPC --account deployer
# done

echo
echo
echo "adding operators..."

OPERATORS=(
    "0x219e66475bc98ff56194E811c37BE523728be8d8" 
    "0xd8b25Ccf45C69E00952e4EAC76b54aed4BEc18b5"
    "0x95e8128d5B9e7Df14c4A7fdce0156E5970E796Bf" 
    "0x1F815DAb2d47cf0661E4843036aD9F56D4aa81cD" 
    "0x6f7601D8Ad9273d3Cd6e40361fF4ec543baa1087" 
    "0xd817035D3570EA17Eb652AA068CBD8c63faE2bE8" 
    "0x11C33C63b18E69b903ED57887DcD6DC7c80237a3" 
    "0x589E1FAf7781954dFea67332AB3ED156acB22615" 
    "0x3397eBD1491302E31786816593c7C08993fb40fa" 
    "0x4B54aa5159a48fD7035D969BAc298A8fd90e6ee4" 
    "0x865b0a1603470c6dDb134eC6A5dEA2921a9e7B1a"
    "0x91Fe39f17E2E41d542c1A085ec6FC44Ad9D6b445"
    )
echo "operators:"
for OP ($OPERATORS); do echo "    $OP"; done

for OP ($OPERATORS)
do 
cast send $PPFX "addOperator(address)()" $OP --rpc-url $RPC --account deployer
done

