// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PPFX} from "../src/PPFX.sol";
import {IPPFX} from "../src/IPPFX.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDT is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(_msgSender(), 100_000_000 ether);
    }
}

contract PPFXTest is Test {
    PPFX public ppfx;
    USDT public usdt;
    address public treasury = address(123400);
    address public insurance = address(1234500);

    function setUp() public {
        usdt = new USDT("USDT", "USDT");
        
        ppfx = new PPFX(
            address(this),
            treasury,
            insurance,
            IERC20(address(usdt)),
            5
        );
    }

    function test_SuccessDeposit() public {
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_AddMarket() public {
        ppfx.addMarket("BTC");
        assertEq(ppfx.totalMarkets(), 1);
    }

    function test_SuccessWithdraw() public {
        test_SuccessDeposit();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.roll(6);
        uint256 oldBalance = usdt.balanceOf(address(this));
        ppfx.claimPendingWithdrawal();
        assertEq(usdt.balanceOf(address(this)), oldBalance + 1 ether);
    }

    function test_SuccessWithdrawTwice() public {
        usdt.approve(address(ppfx), 2 ether);
        ppfx.deposit(2 ether);
        assertEq(ppfx.totalBalance(address(this)), 2 ether);

        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.roll(2);
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 2 ether);
        vm.roll(7);
        uint256 oldBalance = usdt.balanceOf(address(this));
        ppfx.claimPendingWithdrawal();
        assertEq(usdt.balanceOf(address(this)), oldBalance + 2 ether);
    }

    function test_SuccessAddOperator() public {
        assertEq(ppfx.getAllOperators().length, 1);
        ppfx.addOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 2);
    }

    function test_SuccessRemoveOperator() public {
        assertEq(ppfx.getAllOperators().length, 1);
        ppfx.addOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 2);
        ppfx.removeOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 1);
    }

    function test_SuccessRemoveAllOperators() public {
        assertEq(ppfx.getAllOperators().length, 1);
        ppfx.addOperator(address(1));
        assertEq(ppfx.getAllOperators().length, 2);
        ppfx.removeAllOperator();
        assertEq(ppfx.getAllOperators().length, 0);
    }

    function test_SuccessWithdrawAllThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        ppfx.addPosition(address(this), "BTC", 1 ether - 1, 1);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0);
        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessWithdrawHalfThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(0.5 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0.5 ether);
        ppfx.addPosition(address(this), "BTC", 0.8 ether - 1, 1);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0);
        assertEq(ppfx.fundingBalance(address(this)), 0.2 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessWithdrawThenAddPositionWithEnoughFundingBalance() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(0.5 ether);
        ppfx.addPosition(address(this), "BTC", 0.4 ether - 1, 1);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0.5 ether);
        assertEq(ppfx.fundingBalance(address(this)), 0.1 ether);
        assertEq(ppfx.totalBalance(address(this)), 0.5 ether);
    }

    function test_SuccessAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.addPosition(address(this), "BTC", 1 ether - 1, 1);

        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_2ndAddrSuccessAddPosition() public {
        usdt.transfer(address(1), 1 ether);

        vm.startPrank(address(1));
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        vm.stopPrank();

        if (!ppfx.marketExists(keccak256(bytes("BTC")))) {
            test_AddMarket();
        }
        
        ppfx.addPosition(address(1), "BTC", 1 ether - 1, 1);
    }

    function test_SuccessReduceEntirePositionNoProfit() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        ppfx.reducePosition(address(this), "BTC", 1 ether - 1, 0, false, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1);
    }

    function test_SuccessReduceEntirePositionWithProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        // Alice Close Position Entire Position, with 1,000,000,000,000 USDT Profit
        ppfx.reducePosition(address(this), "BTC", 1 ether - 1, 1 ether, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 2 ether - 1);
        assertEq(ppfx.totalBalance(address(this)), 2 ether - 1);
        
        // Bob Liquidate entire position 
        ppfx.liquidate(address(1), "BTC", 0, 1);

        // Bob should have no balance left
        assertEq(ppfx.totalBalance(address(1)), 0);
    }

    function test_SuccessReducePositionOnlyProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice Reduce Position, Getting 1,000,000,000,000 USDT Profit
        // With no reduce in her position
        ppfx.reducePosition(address(this), "BTC", 0, 1 ether, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 2 ether - 1);

        // Bob Liquidate entire position 
        ppfx.liquidate(address(1), "BTC", 0, 1);

        // Bob should have no balance left
        assertEq(ppfx.totalBalance(address(1)), 0);
    }

    function test_SuccessReduceHalfPositionWithAllProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice Reduce Position, Reducing half of her position,
        // and getting 1,000,000,000,000 USDT Profit
        ppfx.reducePosition(address(this), "BTC", 0.5 ether, 1 ether, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1.5 ether);
        assertEq(ppfx.totalBalance(address(this)), 2 ether - 1);

        // Bob Liquidate entire position 
        ppfx.liquidate(address(1), "BTC", 0, 1);

        // Bob should have no balance left
        assertEq(ppfx.totalBalance(address(1)), 0);
    }

    function test_SuccessReduceHalfPositionWithHalfProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice Reduce Position, Reducing half of her position,
        // and getting 500,000,000,000 USDT Profit
        ppfx.reducePosition(address(this), "BTC", 0.5 ether, 0.5 ether, true, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1.5 ether - 1);

        // Bob lose half of his position
        ppfx.reducePosition(address(1), "BTC", 0.5 ether, 0.5 ether, false, 0);
        // Bob should have half of his balance left
        assertEq(ppfx.totalBalance(address(1)), 0.5 ether);
    }

    function test_SuccessReduceNoProfitPosition() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        // Alice Reduce Position, lose fee
        ppfx.reducePosition(address(this), "BTC", 1, 0, false, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1);
    }

    function test_SuccessCloseEntirePositionNoProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice close position with 100% loss
        ppfx.closePosition(address(this), "BTC", 1 ether - 1, false, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessCloseHalfPositionNoProfit() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        // Alice close position with 50% loss
        ppfx.closePosition(address(this), "BTC", 0.5 ether - 1, false, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 0.5 ether);
        assertEq(ppfx.totalBalance(address(this)), 0.5 ether);

        // Bob close position with 50% winning
        ppfx.closePosition(address(1), "BTC", 0.5 ether, true, 0);
        assertEq(ppfx.fundingBalance(address(this)), 0.5 ether);
        assertEq(ppfx.totalBalance(address(1)), 1.5 ether);
    }

    function test_SuccessFillOrder() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        ppfx.fillOrder(address(this), "BTC", 1 gwei);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1 gwei);
        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1 gwei);
    }

    function test_SuccessFillOrderAllBalanceAsFee() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);

        ppfx.fillOrder(address(this), "BTC", 1 ether);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessCancelOrder() public {
        test_SuccessAddPosition();

        ppfx.cancelOrder(address(this), "BTC", 1 ether - 1, 1);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessCancelHalfOrder() public {
        test_SuccessAddPosition();

        ppfx.cancelOrder(address(this), "BTC", 1 ether / 2, 1);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether / 2 + 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessAddFunding() public {
        test_SuccessAddPosition();

        // Deduct funding fee
        ppfx.settleFundingFee(address(this), "BTC", 0.5 ether, false);
        // Then Add funding fee
        ppfx.settleFundingFee(address(this), "BTC", 0.5 ether, true);

        assertEq(ppfx.fundingBalance(address(this)), 0.5 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessDeductFunding() public {
        test_SuccessAddPosition();

        ppfx.settleFundingFee(address(this), "BTC", 1 ether, false);

        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessLiquidateEntireBalance() public {
        test_SuccessAddPosition();

        ppfx.liquidate(address(this), "BTC", 1 gwei, 1 gwei);

        assertEq(usdt.balanceOf(insurance), 1 gwei);
        assertEq(ppfx.totalBalance(address(this)), 1 gwei);
    }

    function test_SuccessLiquidateHalfBalance() public {
        test_SuccessAddPosition();
        uint256 bal = ppfx.getTradingBalanceForMarket(address(this), "BTC");
        ppfx.liquidate(address(this), "BTC", bal / 2, 1 gwei);

        assertEq(usdt.balanceOf(insurance), 1 gwei);
        assertEq(ppfx.fundingBalance(address(this)), bal / 2);
    }

    function test_SuccessAddCollateral() public {
        test_SuccessAddPosition();
        
        usdt.approve(address(ppfx), 1 ether);
        ppfx.deposit(1 ether);
        assertEq(ppfx.fundingBalance(address(this)), 1 ether);

        ppfx.addCollateral(address(this), "BTC", 1 ether);

        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 2 ether);
    }

    function test_SuccessReduceCollateral() public {
        test_SuccessAddPosition();

        ppfx.reduceCollateral(address(this), "BTC", 1 ether);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](40);
        for (uint256 i = 0; i < 30; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_POSITION_SELECTOR(), address(this), "BTC", 1 gwei, 0, false, 0, false);
        }
        for (uint256 i = 30; i < 40; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.REDUCE_POSITION_SELECTOR(), address(this), "BTC", 1 gwei, 0, false, 0, false);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 20 gwei);
    }

    function test_SuccessSingleBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](1);
        for (uint256 i = 0; i < 1; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_COLLATERAL_SELECTOR(), address(this), "BTC", 1 gwei, 0, false, 0, false);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 1 gwei);
    }

    function test_SuccessBulkPositionUpdatesPartiallyFailed() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](30);
        for (uint256 i = 0; i < 10; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_COLLATERAL_SELECTOR(), address(this), "BTC", 1 gwei, 0, false, 0, false);
        }
        for (uint256 i = 10; i < 30; i++) {
            bs[i] = IPPFX.BulkStruct(0x12345678, address(this), "BTC", 1 gwei, 0, false, 0, false);
        }

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 10 gwei);
    }

    function test_SuccessEmptyBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](0);

        ppfx.bulkProcessFunctions(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether);
    }

    function testFail_DepositZero() public {
        ppfx.deposit(0);
        vm.expectRevert(bytes("Invalid amount"));
    }

    function testFail_NoAllowanceDeposit() public {
        ppfx.deposit(1 ether);
        vm.expectRevert(bytes("Insufficient allowance"));
    }

    function testFail_NoAllowanceDepositMax() public {
        ppfx.deposit(2**256-1);
        vm.expectRevert(bytes("Insufficient allowance"));
    }

    function testFail_withdrawMax() public {
        ppfx.withdraw(2**256-1);
        vm.expectRevert(bytes("Insufficient balance from funding account"));
    }

    function testFail_withdrawZero() public {
        ppfx.withdraw(0);
        vm.expectRevert(bytes("Invalid amount"));
    }

    function testFail_UpdateInvalidWithdrawalBlockTime() public {
        ppfx.updateWithdrawalWaitTime(0);
        vm.expectRevert(bytes("Invalid new block time"));
    }

    function testFail_WithdrawBeforeAvailable() public {
        test_SuccessDeposit();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.roll(2);
        ppfx.claimPendingWithdrawal();
        vm.expectRevert(bytes("No available pending withdrawal to claim"));
    }

    function testFail_WithdrawTwiceBeforeAvailable() public {
        usdt.approve(address(ppfx), 2 ether);
        ppfx.deposit(2 ether);
        assertEq(ppfx.totalBalance(address(this)), 2 ether);

        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        vm.roll(2);
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 2 ether);
        vm.roll(6);
        ppfx.claimPendingWithdrawal();
        vm.expectRevert(bytes("No available pending withdrawal to claim"));
    }

    function testFail_WithdrawAllThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(1 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 1 ether);
        ppfx.addPosition(address(this), "BTC", 1 ether, 1);
        vm.expectRevert(bytes("Insufficient funding balance to add position"));
    }

    function testFail_WithdrawHalfThenAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.withdraw(0.5 ether);
        assertEq(ppfx.pendingWithdrawalBalance(address(this)), 0.5 ether);
        ppfx.addPosition(address(this), "BTC", 1 ether, 1);
        vm.expectRevert(bytes("Insufficient funding balance to add position"));
    }

    function testFail_AddPositionInsufficientBalanceForFee() public {
        test_SuccessDeposit();
        test_AddMarket();

        ppfx.addPosition(address(this), "BTC", 1 ether, 1);

        vm.expectRevert(bytes("Insufficient funding balance to add position"));
    }

    function testFail_AddPositionInsufficientBalance() public {
        test_SuccessDeposit();
        test_AddMarket();

        ppfx.addPosition(address(this), "BTC", 1 ether + 1, 0);

        vm.expectRevert(bytes("Insufficient funding balance to add position"));
    }

    function testFail_ReducePositionInsufficientBalanceForFee() public {
        test_SuccessAddPosition();

        ppfx.reducePosition(address(this), "BTC", 1 ether, 0, false, 1);

        vm.expectRevert(bytes("Insufficient trading balance to reduce position"));
    }

    function testFail_ReducePositionInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.reducePosition(address(this), "BTC", 1 ether, 1000000, false, 0);

        vm.expectRevert(bytes("Insufficient trading balance to settle uPNL"));
    }

    function testFail_ClosePositionInsufficientBalanceForFee() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        // Bob Short BTC with 1,000,000,000,000 USDT
        test_2ndAddrSuccessAddPosition(); 

        // Alice close position with 100% profit
        ppfx.closePosition(address(this), "BTC", 1 ether, true, 0);

        // Bob close position with 100% profit which couldn't happen
        ppfx.closePosition(address(1), "BTC", 1 ether, true, 0);

        vm.expectRevert(bytes("Insufficient trading balance to close position"));
    }

    function testFail_ClosePositionCauseInsolvency() public {
        // Alice Long BTC with 1,000,000,000,000 USDT
        test_SuccessAddPosition();
        
        // Close position with 1,000,000,000,001 USDT Porfit
        ppfx.closePosition(address(this), "BTC", 1 ether + 1000000, true, 0);

        vm.expectRevert(bytes("uPNL profit will cause market insolvency"));
    }

    function testFail_FillOrderInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.fillOrder(address(this), "BTC", 2 ether);

        vm.expectRevert(bytes("Insufficient trading balance to pay order filling fee"));
    }

    function testFail_CancelOrderInsufficientBalanceForFee() public {
        test_SuccessAddPosition();

        ppfx.cancelOrder(address(this), "BTC", 1 ether, 1);

        vm.expectRevert(bytes("Insufficient trading balance to cancel order"));
    }

    function testFail_CancelOrderInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.cancelOrder(address(this), "BTC", 1 ether + 1, 0);

        vm.expectRevert(bytes("Insufficient trading balance to cancel order"));
    }

    function testFail_SettleFundingFeeInsufficientCollectedFeeToAdd() public {
        test_SuccessAddPosition();

        ppfx.settleFundingFee(address(this), "BTC", 1 ether, true);

        vm.expectRevert(bytes("Insufficient collected funding fee to add funding fee"));
    }

    function testFail_SettleFundingFeeInsufficientTradingBalanceToDeduct() public {
        test_SuccessAddPosition();

        ppfx.settleFundingFee(address(this), "BTC", 1 ether + 1, false);

        vm.expectRevert(bytes("Insufficient trading balance to deduct funding fee"));
    }

    function testFail_LiquidateInsufficientBalanceForFee() public {
        test_SuccessAddPosition();

        ppfx.liquidate(address(this), "BTC", 1 ether, 1);

        vm.expectRevert(bytes("Insufficient trading balance to liquidate"));
    }

    function testFail_LiquidateInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.liquidate(address(this), "BTC", 1 ether + 1, 0);

        vm.expectRevert(bytes("Insufficient trading balance to liquidate"));
    }

    function testFail_AddCollateralInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.addCollateral(address(this), "BTC", 1);

        vm.expectRevert(bytes("Insufficient funding balance to add collateral"));
    }

    function testFail_ReduceCollateralInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.reduceCollateral(address(this), "BTC", 1 ether + 1);

        vm.expectRevert(bytes("Insufficient trading balance to reduce collateral"));
    }

    function testFail_NotAdmin() public {
        vm.startPrank(address(0));

        ppfx.updateTreasury(address(1));
        vm.expectRevert(bytes("Caller not admin"));

        ppfx.updateInsurance(address(1));
        vm.expectRevert(bytes("Caller not admin"));

        ppfx.updateUsdt(address(1));
        vm.expectRevert(bytes("Caller not admin"));

        ppfx.updateWithdrawalWaitTime(1);
        vm.expectRevert(bytes("Caller not admin"));

        vm.stopPrank();
    }

    function test_AdminFunctions() public {
        ppfx.updateTreasury(address(1));
        assertEq(ppfx.treasury(), address(1));

        ppfx.updateInsurance(address(2));
        assertEq(ppfx.insurance(), address(2));

        ppfx.updateUsdt(address(3));
        assertEq(address(ppfx.usdt()), address(3));

        ppfx.updateWithdrawalWaitTime(444);
        assertEq(ppfx.withdrawalWaitTime(), 444);
    }

    function testFail_NotAdminAddOperator() public {
        vm.startPrank(address(0));
        ppfx.addOperator(address(1));
        vm.expectRevert(bytes("Caller not admin"));
    }

    function testFail_NotAdminRemoveOperator() public {
        vm.startPrank(address(0));
        ppfx.removeOperator(address(this));
        vm.expectRevert(bytes("Caller not admin"));
    }

    function testFail_NotAdminRemoveAllOperators() public {
        vm.startPrank(address(0));
        ppfx.removeAllOperator();
        vm.expectRevert(bytes("Caller not admin"));
    }

    function testFail_RemoveNotExistsOperator() public {
        ppfx.removeOperator(address(3));
        vm.expectRevert(bytes("Operator does not exists"));
    }

    function testFail_NoOperatorRemoveAllOperators() public {
        ppfx.removeAllOperator();
        assertEq(ppfx.getAllOperators().length, 0);
        ppfx.removeAllOperator();
        vm.expectRevert(bytes("No operator found"));
    }

    function testFail_NotOperator() public {
        vm.startPrank(address(0));

        ppfx.addPosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.reducePosition(address(this), "BTC", 1, 0, false, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.closePosition(address(this), "BTC", 1, false, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.fillOrder(address(this), "BTC", 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.cancelOrder(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.settleFundingFee(address(this), "BTC", 1, false);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.liquidate(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.addCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.reduceCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Caller not operator"));

        vm.stopPrank();
    }

    function testFail_CallWithNotExistsMarket() public {
        ppfx.addPosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.reducePosition(address(this), "BTC", 1, 0, false, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.closePosition(address(this), "BTC", 1, false, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.fillOrder(address(this), "BTC", 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.cancelOrder(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.settleFundingFee(address(this), "BTC", 1, false);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.liquidate(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.addCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.reduceCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Provided market does not exists"));
    }

}
