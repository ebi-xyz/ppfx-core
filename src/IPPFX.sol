// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

/**
 * @dev Interface of the PPFX contract
 */
interface IPPFX {
    event NewOperator(address indexed newOperatorAddress);
    event OperatorRemoved(address indexed operatorAddr);
    
    event NewTreasury(address indexed newTreasuryAddress);
    event NewAdmin(address indexed newAdminAddress);
    event NewInsurance(address indexed newInsuranceAddress);
    event NewUSDT(address indexed newUSDTAddress);
    event NewMarketAdded(bytes32 market, string marketName);
    event NewWithdrawalWaitTime(uint256 newWaitTime);
    event NewMinimumOrderAmount(uint256 newMinOrderAmt);
    
    event NewUserTradingVault(address newTradingVaultAddr);
    event NewUserFundingVault(address newFundingVaultAddr);

    event UserDeposit(address indexed user, uint256 amount);
    event UserWithdrawal(address indexed user, uint256 amount, uint256 availableAt);
    event UserClaimedWithdrawal(address indexed user, uint256 amount, uint256 claimedAt);

    event PositionAdded(address indexed user, string market, uint256 size, uint256 fee);
    event PositionReduced(address indexed user, string market, uint256 size, uint256 fee);
    event PositionClosed(address indexed user, string market, uint256 size, uint256 fee);

    event OrderFilled(address indexed user, string market, uint256 fee);

    event OrderCancelled(address indexed user, string market, uint256 size, uint256 fee);

    event FundingSettled(address indexed user, string market, uint256 amount);
    event CollateralAdded(address indexed user, string market, uint256 amount);
    event CollateralDeducted(address indexed user, string market, uint256 amount);

    event Liquidated(address indexed user, string market, uint256 amount, uint256 fee);

    event BulkProcessFailedTxSelectorNotFound(uint256 indexed txIndex, bytes4 methodID);
    event BulkProcessFailedTxReverted(uint256 indexed txIndex, bytes data);

    struct BulkStruct {
        bytes4 methodID;
        address user;
        string marketName;
        uint256 amount;
        uint256 uPNL;
        bool isProfit;
        uint256 fee;
        bool isAdd;
    }

    /**
     * @dev Get Sender total trading balance.
     * @return Sum of sender's trading balance across all available markets.
     */
    function getTradingBalance(address target) external view returns (uint256);

    /**
     * @dev Get target address funding balance.
     * @return Target's funding balance.
     */
    function userFundingBalance(address target) external view returns (uint256);

    /**
     * @dev Get Sender total balance.
     * @return Sum of sender's sum of total trading balance and funding balance.
     */
    function totalBalance(address target) external view returns (uint256);

    /**
     * @dev Get total numbers of available markets.
     * @return The number of available markets.
     */
    function totalMarkets() external view returns (uint256);

    /**
     * @dev Get all available markets.
     */
    function getAllMarkets() external view returns (bytes32[] memory);

    /**
     * @dev Initiate a deposit.
     * @param amount The amount of USDT to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @dev Initiate a withdrawal.
     * @param amount The amount of USDT to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @dev Claim all pending withdrawal
     */
    function claimPendingWithdrawal() external;
}