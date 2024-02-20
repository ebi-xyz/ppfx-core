// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPPFX} from "./IPPFX.sol";

contract PPFX is IPPFX, Context {

    using Math for uint256;
    using SafeERC20 for IERC20;

    address public treasury;
    address public admin;
    address public operator;
    address public insurance;

    IERC20 public usdt;

    uint256 public withdrawalWaitTime;

    mapping(address => mapping(bytes32 => uint256)) public tradingBalance;
    mapping(address => uint256) public fundingBalance;
    mapping(address => uint256) public pendingWithdrawalBalance;
    mapping(address => uint256) public lastWithdrawalBlock;

    mapping(bytes32 => bool) marketExists;
    bytes32[] public availableMarkets;

    modifier onlyAdmin {
        require(_msgSender() == admin, "Caller not admin");
        _;
    }

    modifier onlyOperator {
        require(_msgSender() == operator, "Caller not operator");
        _;
    }

    modifier onlyExistsMarket(string memory marketName) {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        _;
    }

    constructor(address _admin, address _treasury, address _insurance, IERC20 usdtAddress, uint256 _withdrawalWaitTime) {
        _updateAdmin(_admin);
        _updateTreasury(_treasury);
        _updateInsurance(_insurance);
        _updateOperator(_msgSender());
        _updateUsdt(usdtAddress);
        _updateWithdrawalWaitTime(_withdrawalWaitTime);
    }

    function getTradingBalance() external view returns (uint256) {
        return _tradingBalance(_msgSender());
    }

    function totalBalance() external view returns (uint256) {
        return fundingBalance[_msgSender()] + _tradingBalance(_msgSender());
    }

    function totalMarkets() external view returns (uint256) {
        return availableMarkets.length;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(usdt.allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");
        usdt.safeTransferFrom(_msgSender(), address(this), amount);
        fundingBalance[_msgSender()] += amount;
        emit UserDeposit(_msgSender(), amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(fundingBalance[_msgSender()] >= amount, "Insufficient balance from funding account");
        fundingBalance[_msgSender()] -= amount;
        pendingWithdrawalBalance[_msgSender()] += amount;
        lastWithdrawalBlock[_msgSender()] = block.number;
        emit UserWithdrawal(_msgSender(), amount, block.number + withdrawalWaitTime);
    }

    function claimPendingWithdrawal() external {
        require(pendingWithdrawalBalance[_msgSender()] > 0, "Insufficient pending withdrawal balance");
        require(block.number >= lastWithdrawalBlock[_msgSender()] + withdrawalWaitTime, "No available pending withdrawal to claim");
        usdt.safeTransfer(_msgSender(), pendingWithdrawalBalance[_msgSender()]);
        uint256 withdrew = pendingWithdrawalBalance[_msgSender()];
        pendingWithdrawalBalance[_msgSender()] = 0;
        lastWithdrawalBlock[_msgSender()] = 0;
        emit UserClaimedWithdrawal(_msgSender(), withdrew, block.number);
    }

    function addPosition(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator onlyExistsMarket(marketName) {
        uint256 total = size + fee;
        require(fundingBalance[user] >= total, "Insufficient funding balance to add order");
        fundingBalance[user] -= total;
        tradingBalance[user][market] += total;
        emit PositionAdded(user, marketName, size, fee);
    }

    function reducePosition(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator onlyExistsMarket(marketName) {
        uint256 total = size + fee;
        require(tradingBalance[user][market] >= total, "Insufficient trading balance to cancel order");
        tradingBalance[user][market] -= total;
        fundingBalance[user] += size;
        usdt.safeTransfer(treasury, fee);
        emit PositionReduced(user, marketName, size, fee);
    }

    function closePosition(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator onlyExistsMarket(marketName) {
        uint256 total = size + fee;
        require(tradingBalance[user][market] >= total, "Insufficient trading balance to close position");
        tradingBalance[user][market] = 0;
        fundingBalance[user] += size;
        usdt.safeTransfer(treasury, fee);
        emit PositionClosed(user, marketName, size, fee);
    }

    function fillOrder(address user, string memory marketName, uint256 fee) external onlyOperator onlyExistsMarket(marketName) {
        require(tradingBalance[user][market] >= fee, "Insufficient funding balance to pay order filling fee");
        tradingBalance[user][market] -= fee;
        usdt.safeTransfer(treasury, fee);
        emit OrderFilled(user, marketName, fee);
    }

    function cancelOrder(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator onlyExistsMarket(marketName) {
        uint256 total = size + fee;
        require(tradingBalance[user][market] >= total, "Insufficient trading balance to cancel order");
        tradingBalance[user][market] -= total;
        fundingBalance[user] += total;
        emit OrderCancelled(user, marketName, size, fee);
    }

    function addFunding(address user, uint256 amount) external onlyOperator {
        fundingBalance[user] += amount;
        emit FundingAdded(user, amount);
    }

    function deductFunding(address user, string memory marketName, uint256 amount) external onlyOperator onlyExistsMarket(marketName) {
        require(tradingBalance[user][market] >= amount, "Insufficient trading balance to deduct funding");
        tradingBalance[user][market] -= amount;
        emit FundingDeducted(user, marketName,  amount);
    }

    function liquidate(address user, string memory marketName, uint256 amount, uint256 fee) external onlyOperator onlyExistsMarket(marketName) {
        uint256 total = amount + fee;
        require(tradingBalance[user][market] >= total, "Insufficient trading balance to liquidate");
        tradingBalance[user][market] = 0;
        fundingBalance[user] += amount;
        usdt.safeTransfer(insurance, fee);
        emit Liquidated(user, marketName, amount, fee);
    }

    function addCollateral(address user, string memory marketName, uint256 amount) external onlyOperator onlyExistsMarket(marketName) {
        require(fundingBalance[user] >= amount, "Insufficient funding balance to add collateral");
        fundingBalance[user] -= amount;
        tradingBalance[user][market] += amount;
        emit CollateralAdded(user, marketName, amount);
    }

    function reduceCollateral(address user, string memory marketName, uint256 amount) external onlyOperator onlyExistsMarket(marketName) {
        require(tradingBalance[user][market] >= amount, "Insufficient trading balance to reduce collateral");
        tradingBalance[user][market] -= amount;
        fundingBalance[user] += amount;
        emit CollateralDeducted(user, marketName, amount);
    }


    function addMarket(string memory marketName) external onlyOperator() {
        _addMarket(marketName);
    }

    function updateTreasury(address treasuryAddr) external onlyAdmin {
        _updateTreasury(treasuryAddr);
    }

    function updateOperator(address operatorAddr) external onlyAdmin {
        _updateOperator(operatorAddr);
    }

    function updateInsurance(address insuranceAddr) external onlyAdmin {
        _updateInsurance(insuranceAddr);
    }

    function updateUsdt(address newUSDT) external onlyAdmin {
        _updateUsdt(IERC20(newUSDT));
    }

    function updateWithdrawalWaitTime(uint256 newBlockTime) external onlyAdmin {
        require(newBlockTime > 0, "Invalid new block time");
        _updateWithdrawalWaitTime(newBlockTime);
    }


    function _tradingBalance(address user) internal view returns (uint256) {
        uint256 balSum = 0;
        for (uint i = 0; i < availableMarkets.length; i++) {
            balSum += tradingBalance[user][availableMarkets[i]];
        }
        return balSum;
    }

    function _marketHash(string memory marketName) internal pure returns (bytes32) {
        return keccak256(abi.encode(marketName));
    }

    function _addMarket(string memory marketName) internal {
        bytes32 market = _marketHash(marketName);
        availableMarkets.push(market);
        marketExists[market] = true;
        emit NewMarketAdded(market, marketName);
    }

    function _updateAdmin(address adminAddr) internal {
        admin = adminAddr;
        emit NewAdmin(adminAddr);
    }

    function _updateTreasury(address treasuryAddr) internal {
        treasury = treasuryAddr;
        emit NewTreasury(treasuryAddr);
    }

    function _updateOperator(address operatorAddr) internal {
        operator = operatorAddr;
        emit NewOperator(operatorAddr);
    }

    function _updateInsurance(address insuranceAddr) internal {
        insurance = insuranceAddr;
        emit NewInsurance(insuranceAddr);
    }

    function _updateUsdt(IERC20 newUSDT) internal {
        usdt = newUSDT;
        emit NewUSDT(address(newUSDT));
    }

    function _updateWithdrawalWaitTime(uint256 newBlockTime) internal {
        withdrawalWaitTime = newBlockTime;
        emit NewWithdrawalWaitTime(newBlockTime);
    }
}
