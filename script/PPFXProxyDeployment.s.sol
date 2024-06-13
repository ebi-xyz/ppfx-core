pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {PPFX} from "../src/PPFX.sol";

contract PPFXProxyDeploymentScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        Options memory opts;
        opts.unsafeAllow = "delegatecall";

        Upgrades.deployTransparentProxy(
            "PPFX.sol",
            vm.envAddress("ADMIN"),
            abi.encodeCall(PPFX.initialize, (
                vm.envAddress("ADMIN"),
                vm.envAddress("TREASURY"),
                vm.envAddress("INSURANCE"),
                IERC20(vm.envAddress("USDT")),
                vm.envUint("WITHDRAW_WAIT_TIME"),
                vm.envUint("MIN_ORDER_AMT"),
                vm.envString("PPFX_VERSION")
            )),
            opts
        );
        vm.stopBroadcast();
    }
}