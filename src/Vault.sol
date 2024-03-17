// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Vault is Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;

    mapping(address => mapping(bytes32 => uint256)) public balances;

    constructor(IERC20 _token) Ownable(_msgSender()) {
        token = _token;
    }

    function deposit(address user, bytes32 place, uint256 amount) external onlyOwner {
        require(token.balanceOf(user) >= amount, "Insufficient balance to deposit");
        token.safeTransferFrom(_msgSender(), address(this), amount);
        balances[user][place] += amount;
    }

    function withdraw(address user, bytes32 place, uint256 amount) external onlyOwner {
        require(balances[user][place] >= amount, "Insufficient balance to withdraw");
        token.safeTransfer(_msgSender(), amount);
        balances[user][place] -= amount;
    }

    function deposit(address user, uint256 amount) external onlyOwner {
        require(token.balanceOf(user) >= amount, "Insufficient balance to deposit");
        token.safeTransferFrom(_msgSender(), address(this), amount);
        balances[user][addrToBytes32(user)] += amount;
    }

    function withdraw(address user, uint256 amount) external onlyOwner {
        bytes32 addrBytes32 = addrToBytes32(user);
        require(balances[user][addrBytes32] >= amount, "Insufficient balance to withdraw");
        token.safeTransfer(_msgSender(), amount);
        balances[user][addrBytes32] -= amount;
    }

    function migrateToNewVault(address newVaultAddr) external onlyOwner {
        token.safeTransfer(newVaultAddr, token.balanceOf(address(this)));
    }

    function getUserTotalBalance(address user, bytes32[] memory places) external view returns (uint256) {
        uint256 balSum = 0;
        for (uint i = 0; i < places.length; i++) {
            balSum += balances[user][places[i]];
        }
        return balSum;
    }

    function getUserBalance(address user, bytes32 place) external view returns (uint256) {
        return balances[user][place];
    }

     function getUserBalance(address user) external view returns (uint256) {
        return balances[user][addrToBytes32(user)];
    }

    function addrToBytes32(address user) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(user)) << 96);
    }
}