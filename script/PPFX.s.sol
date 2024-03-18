// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PPFX} from "../src/PPFX.sol";

// https://github.com/matter-labs/local-setup/blob/main/rich-wallets.json
contract USDT is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(_msgSender(), 100_000_000_000 ether);
    }
}

contract PPFXScript is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        USDT usdt = new USDT("USDT", "USDT");
        
        PPFX ppfx = new PPFX(
            deployerAddr,
            deployerAddr,
            deployerAddr,
            IERC20(address(usdt)),
            5
        );

        vm.stopBroadcast();
    }
}
