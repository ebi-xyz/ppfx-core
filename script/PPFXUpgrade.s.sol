// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract PPFXProxyUpgradeScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        Options memory opts;
        opts.unsafeAllow = "delegatecall";
        opts.referenceContract = "PPFX.sol";

        Upgrades.upgradeProxy(
            vm.envAddress("PPFX"),
            "PPFX_Upgraded.sol",
            "",
            opts
        );

        vm.stopBroadcast();
    }
}