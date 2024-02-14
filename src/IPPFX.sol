// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

interface IPPFX {
    event NewTreasury(address indexed newTreasuryAddress);
    event NewOperator(address indexed newOperatorAddress);
    event NewAdmin(address indexed newAdminAddress);
    event NewInsurance(address indexed newInsuranceAddress);
    event NewUSDT(address indexed newUSDTAddress);
    event NewMarketAdded(bytes32 market, string marketName);
    
    event UserDeposit(address indexed user, uint256 amount);
    event UserWithdrawal(address indexed user, uint256 amount, uint256 availableAt);
    event UserClaimedWithdrawal(address indexed user, uint256 amount, uint256 claimedAtBlock);

    event PositionAdded(address indexed user, bytes32 market, uint256 size, uint256 fee);
    event PositionReduced(address indexed user, bytes32 market, uint256 size, uint256 fee);
    event PositionClosed(address indexed user, bytes32 market, uint256 size, uint256 fee);
    event OrderFilled(address indexed user, bytes32 market, uint256 fee);
    event OrderCancelled(address indexed user, bytes32 market, uint256 size, uint256 fee);
    event FundingAdded(address indexed user, uint256 amount);
    event FundingDeducted(address indexed user, bytes32 market, uint256 amount);
    event CollateralAdded(address indexed user, bytes32 market, uint256 amount);
    event CollateralDeducted(address indexed user, bytes32 market, uint256 amount);
    event Liquidated(address indexed user, bytes32 market, uint256 amount, uint256 fee);

    event NewWithdrawalWaitTime(uint256 newWaitTime);

    function getTradingBalance() external view returns (uint256);
    function totalBalance() external view returns (uint256);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimPendingWithdrawal() external;
}