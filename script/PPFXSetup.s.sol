pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PPFX} from "../src/PPFX.sol";
import {strings} from "solidity-stringutils/src/strings.sol";

contract PPFXSetupScript is Script {
    using strings for *;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PPFX ppfx = PPFX(vm.envAddress("PPFX"));

        strings.slice memory sep = " ".toSlice();

        strings.slice memory marketSlice = vm.envString("MARKETS").toSlice();

        uint totalLen = marketSlice.count(sep) + 1;
        for(uint i = 0; i < totalLen; i++) {
            string memory marketName = marketSlice.split(sep).toString();
            if (!ppfx.marketExists(keccak256(bytes(marketName)))) {
                ppfx.addMarket(marketName);
                console.log("Added Market:", marketName);
            } else {
                console.log("Market already exists:", marketName);
            }
        }

        address[] memory operators = vm.envAddress("OPERATORS", ",");
        for(uint i = 0; i < operators.length; i++) {
            address operatorAddr = operators[i];
            if (!ppfx.isOperator(operatorAddr)) {
                ppfx.addOperator(operatorAddr);
                console.log("Added new operator:", operatorAddr);
            } else {
                console.log(operatorAddr, "already an operator");
            }
        }
        vm.stopBroadcast();   
    }
}