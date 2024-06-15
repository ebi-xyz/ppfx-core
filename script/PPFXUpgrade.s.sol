// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract PPFXProxyUpgradeScript is Script {
    struct PPFXConfig {
        address ppfx;
        string ppfxFileName;
        string newPPFXFileName;
    }

    PPFXConfig config;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/config/ppfxConfig.json");
        string memory json = vm.readFile(path);

        address ppfx = vm.parseJsonAddress(json, ".ppfx");
        string memory ppfxFileName = vm.parseJsonString(json, ".ppfxFileName");
        string memory newPPFXFileName = vm.parseJsonString(json, ".newPPFXFileName");

        config = PPFXConfig(
            ppfx,
            ppfxFileName,
            newPPFXFileName
        );
    }

    function run() public {
        vm.startBroadcast();

        Options memory opts;
        opts.unsafeAllow = "delegatecall";
        opts.referenceContract = config.ppfxFileName;

        Upgrades.upgradeProxy(
            config.ppfx,
            config.newPPFXFileName,
            "",
            opts
        );

        vm.stopBroadcast();
    }
}