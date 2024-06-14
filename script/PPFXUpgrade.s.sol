// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract PPFXProxyUpgradeScript is Script {
    struct PPFXStrConfig {
        string ppfxFileName;
        string newPPFXFileName;
        string ppfxVersion;
        string[] markets;
        address[] operators;
    }

    struct PPFXUpgradeConfig {
        address ppfx;
    }

    PPFXUpgradeConfig config;
    PPFXStrConfig strConfig;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/config/ppfxUpgradeConfig.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        config = abi.decode(data, (PPFXUpgradeConfig));

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
        vm.startBroadcast();

        Options memory opts;
        opts.unsafeAllow = "delegatecall";
        opts.referenceContract = strConfig.ppfxFileName;

        Upgrades.upgradeProxy(
            config.ppfx,
            strConfig.newPPFXFileName,
            "",
            opts
        );

        vm.stopBroadcast();
    }
}