// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./mocks/MockUSDT.sol";
import "../src/PPFX.sol";

contract USDTUpgradeTest is Test {
    PPFX private ppfx;
    uint256 mainnetFork;

    address constant PPFX_ADDRESS = address(0xA60e2bf9A6D7B8e9d0f928308A77353dFE1c71Ca);
    
    address admin = address(0xB9D192544F29Fb1d734610BfEeDA627F34dC91dd);
    address user = makeAddr("user");
    address operator = address(0xAA5e41462e6B70ABe5d636A84eb818567CCc750f);

    IERC20 oldUSDT = IERC20(0x5489DDAb89609580835eE6d655CD9B3503E7F97D); // Mainnet USDT
    MockUSDT newUSDT;

    function setUp() public {
        mainnetFork = vm.createFork("wss://rpc.ebi.xyz");
        vm.selectFork(mainnetFork);

        // Deploy new mock USDT
        newUSDT = new MockUSDT();
        
        ppfx = PPFX(PPFX_ADDRESS);

        // Fund user
        deal(address(oldUSDT), user, 1000e6);
        newUSDT.mockMint(user, 1000e6);

        console.log("Initial Balances:");
        console.log("Old USDT Balance:", oldUSDT.balanceOf(user));
        console.log("New USDT Balance:", newUSDT.balanceOf(user));
        console.log("PPFX Funding Balance:", ppfx.userFundingBalance(user));
    }

    function testUSDTUpgrade() public {
        vm.startPrank(user);
        oldUSDT.approve(address(ppfx), 500e6);
        ppfx.deposit(500e6);
        vm.stopPrank();

        console.log("\nAfter First Deposit:");
        console.log("Old USDT Balance:", oldUSDT.balanceOf(user));
        console.log("PPFX Funding Balance:", ppfx.userFundingBalance(user));

        vm.prank(admin);
        ppfx.updateUsdt(address(newUSDT));

        vm.startPrank(user);
        newUSDT.approve(address(ppfx), 300e6);
        ppfx.deposit(300e6);
        vm.stopPrank();

        console.log("\nAfter Second Deposit:");
        console.log("New USDT Balance:", newUSDT.balanceOf(user));
        console.log("PPFX Funding Balance:", ppfx.userFundingBalance(user));

        vm.prank(operator);
        ppfx.addPosition(user, "ETH-USDT", 400e6, 1e6);

        console.log("\nAfter Adding Position:");
        console.log("PPFX Funding Balance:", ppfx.userFundingBalance(user));
        console.log("ETH-USDT Trading Balance:", ppfx.getTradingBalanceForMarket(user, "ETH-USDT"));

        vm.prank(admin);
        ppfx.updateUsdt(address(oldUSDT));

        console.log("\nAfter Rollback:");
        console.log("PPFX Funding Balance:", ppfx.userFundingBalance(user));
        console.log("ETH-USDT Trading Balance:", ppfx.getTradingBalanceForMarket(user, "ETH-USDT"));
    }
}
