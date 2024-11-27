// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITarget {
    function getTradingBalance(address target) external view returns (uint256);
    function totalBalance(address target) external view returns (uint256);
    function getTradingBalanceForMarket(address target, string calldata marketName) external view returns (uint256);
    function pendingWithdrawalBalance(address target) external view returns (uint256);
    function lastWithdrawalTime(address target) external view returns (uint256);
}

contract BalanceMulticall {
    struct Result {
        uint256 tradingBalance;
        uint256 totalBalance;
        uint256 pendingWithdrawalBalance;
        uint256 lastWithdrawalTime;
        uint256[] marketBalances;
    }

    function getMultipleBalances(address target, address[] calldata users, string[] calldata markets) external view returns (Result[] memory) {
        Result[] memory results = new Result[](users.length);
        ITarget targetContract = ITarget(target);

        for(uint i = 0; i < users.length; i++) {
            results[i].tradingBalance = targetContract.getTradingBalance(users[i]);
            results[i].totalBalance = targetContract.totalBalance(users[i]);
            results[i].pendingWithdrawalBalance = targetContract.pendingWithdrawalBalance(users[i]);
            results[i].lastWithdrawalTime = targetContract.lastWithdrawalTime(users[i]);
            results[i].marketBalances = new uint256[](markets.length);
            for(uint j = 0; j < markets.length; j++) {
                results[i].marketBalances[j] = targetContract.getTradingBalanceForMarket(users[i], markets[j]);
            }
        }

        return results;
    }
}
