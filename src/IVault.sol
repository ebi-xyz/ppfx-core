// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

/**
 * @dev Interface of the PPFX contract
 */
interface IVault {
    function deposit(address user, bytes32 place, uint256 amount) external;
    function deposit(address user, uint256 amount) external;
    function withdraw(address user, bytes32 place, uint256 amount) external;
    function withdraw(address user, uint256 amount) external;
    function getUserTotalBalance(address user, bytes32[] memory places) external view returns (uint256);
    function getUserBalance(address user, bytes32 place) external view returns (uint256);
    function getUserBalance(address user) external view returns (uint256);
    function migrateToNewVault(address newVaultAddr) external;
}