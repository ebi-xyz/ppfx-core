// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PPFX} from "../src/PPFX.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract PPFXTest is Test {
    PPFX public ppfx;

    function setUp() public {
        ppfx = new PPFX(
            address(0),
            address(0),
            address(0),
            IERC20(address(0)),
            10
        );
    }
}
