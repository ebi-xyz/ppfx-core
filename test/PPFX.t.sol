// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
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

        Vault fundingVault = new Vault(usdt);
        Vault tradingVault = new Vault(usdt);
        
        ppfx = new PPFX(
            address(this),
            treasury,
            insurance,
            IERC20(address(usdt)),
            address(fundingVault),
            address(tradingVault),
            5
        );

        fundingVault.transferOwnership(address(ppfx));
        tradingVault.transferOwnership(address(ppfx));
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

    function test_SuccessAddPosition() public {
        test_SuccessDeposit();
        test_AddMarket();
        ppfx.addPosition(address(this), "BTC", 1 ether - 1, 1);

        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessReduceEntirePosition() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        ppfx.reducePosition(address(this), "BTC", 1 ether - 1, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1);
    }

    function test_SuccessReducePosition() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        ppfx.reducePosition(address(this), "BTC", 1, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1);
        assertEq(ppfx.totalBalance(address(this)), 1 ether - 1);
    }

    function test_SuccessCloseEntirePosition() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        ppfx.closePosition(address(this), "BTC", 0, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 0);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessClosePosition() public {
        test_SuccessAddPosition();
        uint256 oldTreasuryBalance = usdt.balanceOf(treasury);
        ppfx.closePosition(address(this), "BTC", 1 gwei, 1);

        assertEq(usdt.balanceOf(treasury), oldTreasuryBalance + 1);
        assertEq(ppfx.fundingBalance(address(this)), 1 gwei);
        assertEq(ppfx.totalBalance(address(this)), 1 gwei);
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

    function test_SuccessSettleFunding() public {
        test_SuccessAddPosition();

        ppfx.settleFundingFee(address(this), "BTC", 1 ether);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether);
        assertEq(ppfx.totalBalance(address(this)), 1 ether);
    }

    function test_SuccessLiquidateEntireBalance() public {
        test_SuccessAddPosition();

        ppfx.liquidate(address(this), "BTC", 0, 1 gwei);

        assertEq(usdt.balanceOf(insurance), 1 gwei);
        assertEq(ppfx.totalBalance(address(this)), 0);
    }

    function test_SuccessLiquidateHalfBalance() public {
        test_SuccessAddPosition();

        ppfx.liquidate(address(this), "BTC", 1 ether / 2 - 1 gwei, 1 gwei);

        assertEq(usdt.balanceOf(insurance), 1 gwei);
        assertEq(ppfx.totalBalance(address(this)), 1 ether / 2 - 1 gwei);
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
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_POSITION_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }
        for (uint256 i = 30; i < 40; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.REDUCE_POSITION_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctionsWithFee(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 20 gwei);
    }

    function test_SuccessBulkPositionWithoutFeeUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](40);
        for (uint256 i = 0; i < 30; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_COLLATERAL_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }
        for (uint256 i = 30; i < 40; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.REDUCE_COLLATERAL_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctionsWithoutFee(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 20 gwei);
    }

    function test_SuccessSingleBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](1);
        for (uint256 i = 0; i < 1; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_POSITION_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }
        ppfx.bulkProcessFunctionsWithFee(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 1 gwei);
    }

    function test_SuccessSingleBulkPositionWithoutFeeUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](1);
        for (uint256 i = 0; i < 1; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_COLLATERAL_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctionsWithoutFee(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether - 1 gwei);
    }

    function test_SuccessEmptyBulkPositionUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](0);

        ppfx.bulkProcessFunctionsWithFee(bs);

        assertEq(ppfx.fundingBalance(address(this)), 1 ether);
    }

    function test_SuccessEmptyBulkPositionWithoutFeeUpdates() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](0);

        ppfx.bulkProcessFunctionsWithoutFee(bs);

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

        ppfx.reducePosition(address(this), "BTC", 1 ether, 1);

        vm.expectRevert(bytes("Insufficient trading balance to reduce position"));
    }

    function testFail_ReducePositionInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.reducePosition(address(this), "BTC", 1 ether + 1, 0);

        vm.expectRevert(bytes("Insufficient trading balance to reduce position"));
    }

    function testFail_ClosePositionInsufficientBalanceForFee() public {
        test_SuccessAddPosition();

        ppfx.closePosition(address(this), "BTC", 1 ether, 1);

        vm.expectRevert(bytes("Insufficient trading balance to close position"));
    }

    function testFail_ClosePositionInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.closePosition(address(this), "BTC", 1 ether + 1, 0);

        vm.expectRevert(bytes("Insufficient trading balance to close position"));
    }

    function testFail_FillOrderInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.fillOrder(address(this), "BTC", 1);

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

    function testFail_SettleFundingFeeInsufficientBalance() public {
        test_SuccessAddPosition();

        ppfx.settleFundingFee(address(this), "BTC", 1 ether + 1);

        vm.expectRevert(bytes("Insufficient trading balance to settle funding"));
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

    function testFail_BulkUpdatesSelectorNotFound() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](40);
        for (uint256 i = 0; i < 30; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_POSITION_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }
        for (uint256 i = 30; i < 40; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.REDUCE_COLLATERAL_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctionsWithFee(bs);

        vm.expectRevert(bytes("FunctionSelectorNotFound"));
    }

    function testFail_BulkUpdatesWithoutFeeSelectorNotFound() public {
        test_SuccessDeposit();
        test_AddMarket();
       
        IPPFX.BulkStruct[] memory bs = new PPFX.BulkStruct[](40);
        for (uint256 i = 0; i < 30; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.ADD_COLLATERAL_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }
        for (uint256 i = 30; i < 40; i++) {
            bs[i] = IPPFX.BulkStruct(ppfx.REDUCE_POSITION_SELECTOR(), address(this), "BTC", 1 gwei, 0);
        }

        ppfx.bulkProcessFunctionsWithoutFee(bs);

        vm.expectRevert(bytes("FunctionSelectorNotFound"));
    }

    function testFail_NotAdmin() public {
        vm.prank(address(0));

        ppfx.updateTreasury(address(1));
        vm.expectRevert(bytes("Caller not admin"));

        ppfx.updateOperator(address(1));
        vm.expectRevert(bytes("Caller not admin"));

        ppfx.updateInsurance(address(1));
        vm.expectRevert(bytes("Caller not admin"));

        ppfx.updateUsdt(address(1));
        vm.expectRevert(bytes("Caller not admin"));

        ppfx.updateWithdrawalWaitTime(1);
        vm.expectRevert(bytes("Caller not admin"));
    }

    function test_AdminFunctions() public {
        ppfx.updateTreasury(address(1));
        assertEq(ppfx.treasury(), address(1));

        ppfx.updateOperator(address(1));
        assertEq(ppfx.operator(), address(1));

        ppfx.updateInsurance(address(2));
        assertEq(ppfx.insurance(), address(2));

        ppfx.updateUsdt(address(3));
        assertEq(address(ppfx.usdt()), address(3));

        ppfx.updateWithdrawalWaitTime(444);
        assertEq(ppfx.withdrawalWaitTime(), 444);
    }

    function testFail_NotOperator() public {
        vm.prank(address(0));

        ppfx.addPosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.reducePosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.closePosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.fillOrder(address(this), "BTC", 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.cancelOrder(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.settleFundingFee(address(this), "BTC", 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.liquidate(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.addCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Caller not operator"));

        ppfx.reduceCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Caller not operator"));
    }

    function testFail_CallWithNotExistsMarket() public {
        ppfx.addPosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.reducePosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.closePosition(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.fillOrder(address(this), "BTC", 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.cancelOrder(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.settleFundingFee(address(this), "BTC", 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.liquidate(address(this), "BTC", 1, 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.addCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Provided market does not exists"));

        ppfx.reduceCollateral(address(this), "BTC", 1);
        vm.expectRevert(bytes("Provided market does not exists"));
    }

}
