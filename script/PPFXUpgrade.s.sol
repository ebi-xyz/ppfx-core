// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract PPFXProxyUpgradeScript is Script {
    struct UpgradeConfig {
        string ppfxFileName;
        string newPpfxFileName;
        address ppfx;
    }

    PPFXConfig config;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/config/ppfxConfig.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        config = abi.decode(data, (PPFXConfig));
    }

    function run() public {
        require(config.ppfx != address(0), "PPFXDeployment: PPFX address can not be null");
        require(bytes(config.ppfxFileName).length > 0, "PPFXDeployment: PPFX File Name can not be empty");
        require(bytes(config.newPpfxFileName).length > 0, "PPFXDeployment: New PPFX File Name can not be empty");
        vm.startBroadcast();

        Options memory opts;
        opts.unsafeAllow = "delegatecall";
        opts.referenceContract = config.ppfxFileName;

        Upgrades.upgradeProxy(
            config.ppfx,
            config.newPpfxFileName,
            "",
            opts
        );

        vm.stopBroadcast();
    }
}