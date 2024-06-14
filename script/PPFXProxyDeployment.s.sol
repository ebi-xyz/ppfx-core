pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {PPFX} from "../src/PPFX.sol";

import {PPFX} from "../src/PPFX.sol";

contract PPFXProxyDeploymentScript is Script {

    struct PPFXConfig {
        address admin;
        address insurance;
        address treasury;
        address usdt;

        uint256 minOrderAmount;
        uint256 withdrawWaitTime;
    }

    struct PPFXStrConfig {
        string ppfxFileName;
        string newPPFXFileName;
        string ppfxVersion;
        string[] markets;
        address[] operators;
    }

    PPFXConfig config;
    PPFXStrConfig strConfig;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/config/ppfxConfig.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);

        config = abi.decode(data, (PPFXConfig));

        string memory strPath = string.concat(root, "/config/ppfxStrConfig.json");
        string memory strJson = vm.readFile(strPath);

        string memory ppfxFileName = vm.parseJsonString(strJson, ".ppfxFileName");
        string memory newPPFXFileName = vm.parseJsonString(strJson, ".newPPFXFileName");
        string memory version = vm.parseJsonString(strJson, ".ppfxVersion");
        string[] memory markets = vm.parseJsonStringArray(strJson, ".markets");
        address[] memory operators = vm.parseJsonAddressArray(strJson, ".operators");
        strConfig = PPFXStrConfig(
            ppfxFileName,
            newPPFXFileName,
            version,
            markets,
            operators
        );
    }

    function run() public {
        require(config.admin != address(0), "PPFXDeployment: Admin address can not be null");
        require(config.insurance != address(0), "PPFXDeployment: Insurance address can not be null");
        require(config.treasury != address(0), "PPFXDeployment: Treasury address can not be null");
        require(config.usdt != address(0), "PPFXDeployment: USDT address can not be null");
        require(config.minOrderAmount > 0, "PPFXDeployment: MinOrderAmount can not be zero");
        require(config.withdrawWaitTime > 0, "PPFXDeployment: WithdrawWaitTime can not be zero");
        require(bytes(strConfig.ppfxVersion).length > 0, "PPFXDeployment: PPFX Version can not be empty");
        require(bytes(strConfig.ppfxFileName).length > 0, "PPFXDeployment: PPFX File Name can not be empty");

        vm.startBroadcast();

        Options memory opts;
        opts.unsafeAllow = "delegatecall";

        address proxyAddr = Upgrades.deployTransparentProxy(
            strConfig.ppfxFileName,
            config.admin,
            abi.encodeCall(PPFX.initialize, (
                config.admin,
                config.treasury,
                config.insurance,
                IERC20(config.usdt),
                config.withdrawWaitTime,
                config.minOrderAmount,
                strConfig.ppfxVersion
            )),
            opts
        );

        PPFX deployedPPFX = PPFX(proxyAddr);
        uint marketLen = strConfig.markets.length;
        
        if (marketLen > 0) {
            console.log("Start adding markets to deployed PPFX...");
            for(uint i = 0; i < marketLen; i++) {
                string memory marketName = strConfig.markets[i];
                if (!deployedPPFX.marketExists(keccak256(bytes(marketName)))) {
                    deployedPPFX.addMarket(marketName);
                    console.log("Added Market:", marketName);
                } else {
                    console.log("Market already exists:", marketName);
                }
            }
        } else {
            console.log("No Markets found in config");
        }
        
        uint operatorLen = strConfig.operators.length;

        if (operatorLen > 0) {
            console.log("Start adding operators to deployed PPFX...");
            for(uint i = 0; i < operatorLen; i++) {
                address operatorAddr = strConfig.operators[i];
                if (!deployedPPFX.isOperator(operatorAddr)) {
                    deployedPPFX.addOperator(operatorAddr);
                    console.log("Added new operator:");
                    console.logAddress(operatorAddr);
                } else {
                    console.logAddress(operatorAddr);
                    console.log( "already an operator");
                }
            }
        } else {
            console.log("No Operators Found in config");
        }

        console.log("=== Successfully Deployed & Setup PPFX ===");

        address implAddr = Upgrades.getImplementationAddress(proxyAddr);
        console.log("PPFX Implementation Deployed at:");
        console.logAddress(implAddr);

        console.log("PPFX Proxy Deployed at:");
        console.logAddress(proxyAddr);

        console.log("Available Markets:");
        bytes32[] memory allMarkets = deployedPPFX.getAllMarkets();
        for (uint i = 0; i < allMarkets.length; i ++) {
            console.logBytes32(allMarkets[i]);
        }

        console.log("\n\n");

        console.log("PPFX Operators:");
        address[] memory allOperators = deployedPPFX.getAllOperators();
        for (uint i = 0; i < allOperators.length; i ++) {
            console.logAddress(allOperators[i]);
        }

        vm.stopBroadcast();
    }
}