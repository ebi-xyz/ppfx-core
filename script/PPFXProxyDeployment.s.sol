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

        string ppfxFileName;
        string ppfxVersion;
        string[] markets;
        address[] operators;
    }

    PPFXConfig config;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/config/ppfxConfig.json");
        string memory json = vm.readFile(path);

        string memory ppfxFileName = vm.parseJsonString(json, ".ppfxFileName");
        string memory version = vm.parseJsonString(json, ".ppfxVersion");
        string[] memory markets = vm.parseJsonStringArray(json, ".markets");
        address[] memory operators = vm.parseJsonAddressArray(json, ".operators");

        address admin = vm.parseJsonAddress(json, ".admin");
        address insurance = vm.parseJsonAddress(json, ".insurance");
        address treasury = vm.parseJsonAddress(json, ".treasury");
        address usdt = vm.parseJsonAddress(json, ".usdt");

        uint256 minOrderAmount = vm.parseJsonUint(json, ".minOrderAmount");
        uint256 withdrawWaitTime = vm.parseJsonUint(json, ".withdrawWaitTime");
       
        config = PPFXConfig(
            admin,
            insurance,
            treasury,
            usdt,
            minOrderAmount,
            withdrawWaitTime,
            ppfxFileName,
            version,
            markets,
            operators
        );

        console.log("setup() loaded config:");
        console.log("Admin: %o", admin);
        console.log("Insurance: %o", insurance);
        console.log("Treasury: %o", treasury);
        console.log("USDT: %o", usdt);
        console.log("Min Order Amount: %d", minOrderAmount);
        console.log("Withdraw wait time: %d", withdrawWaitTime);
    }

    function run() public {
        require(config.admin != address(0), "PPFXDeployment: Admin address can not be null");
        require(config.insurance != address(0), "PPFXDeployment: Insurance address can not be null");
        require(config.treasury != address(0), "PPFXDeployment: Treasury address can not be null");
        require(config.usdt != address(0), "PPFXDeployment: USDT address can not be null");
        require(config.minOrderAmount > 0, "PPFXDeployment: MinOrderAmount can not be zero");
        require(config.withdrawWaitTime > 0, "PPFXDeployment: WithdrawWaitTime can not be zero");
        require(bytes(config.ppfxVersion).length > 0, "PPFXDeployment: PPFX Version can not be empty");
        require(bytes(config.ppfxFileName).length > 0, "PPFXDeployment: PPFX File Name can not be empty");

        vm.startBroadcast();

        Options memory opts;
        opts.unsafeAllow = "delegatecall";

        address proxyAddr = Upgrades.deployTransparentProxy(
            config.ppfxFileName,
            config.admin,
            abi.encodeCall(PPFX.initialize, (
                config.admin,
                config.treasury,
                config.insurance,
                IERC20(config.usdt),
                config.withdrawWaitTime,
                config.minOrderAmount,
                config.ppfxVersion
            )),
            opts
        );

        PPFX deployedPPFX = PPFX(proxyAddr);
        uint marketLen = config.markets.length;
        
        if (marketLen > 0) {
            console.log("Start adding markets to deployed PPFX...");
            for(uint i = 0; i < marketLen; i++) {
                string memory marketName = config.markets[i];
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
        
        uint operatorLen = config.operators.length;

        if (operatorLen > 0) {
            console.log("Start adding operators to deployed PPFX...");
            for(uint i = 0; i < operatorLen; i++) {
                address operatorAddr = config.operators[i];
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