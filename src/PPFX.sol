// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IPPFX} from "./IPPFX.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract PPFX is IPPFX, Context, Initializable, EIP712Upgradeable, NoncesUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    using Math for uint256;
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant WITHDRAW_FOR_USER_TYPEHASH = keccak256("withdrawForUser(address delegate,address from,uint256 amount,uint256 nonce,uint48 deadline)");
    bytes32 public constant CLAIM_FOR_USER_TYPEHASH = keccak256("claimPendingWithdrawalForUser(address delegate,address from,uint256 nonce,uint48 deadline)");
    uint256 public constant MAX_OPERATORS = 25;

    address public withdrawHook;
    address public treasury;
    address public admin;
    address public insurance;
    
    address private pendingAdmin;
    EnumerableSet.AddressSet private operators;

    IERC20 public usdt;

    uint256 public minimumOrderAmount;
    uint256 public withdrawalWaitTime;
    uint256 public totalTradingBalance;

    uint256 public availableFundingFee;

    mapping(bytes32 => uint256) public marketTotalTradingBalance;
    mapping(address => mapping(bytes32 => uint256)) public userTradingBalance;
    mapping(address => uint256) public userFundingBalance;

    mapping(address => uint256) public pendingWithdrawalBalance;
    mapping(address => uint256) public lastWithdrawalTime;

    mapping(bytes32 => bool) public marketExists;
    bytes32[] public availableMarkets;

    /**
     * @dev Throws if called by any account other than the Admin
     */
    modifier onlyAdmin {
        require(_msgSender() == admin, "Caller not admin");
        _;
    }

    /**
     * @dev Throws if called by any account other than the Operator
     */
    modifier onlyOperator {
        require(operators.contains(_msgSender()), "Caller not operator");
        _;
    }

    /**
     * @dev Throws if called by any account other than the Withdraw Hook
     */
    modifier onlyWithdrawHook {
        require(_msgSender() == withdrawHook, "Caller not withdraw hook");
        _;
    }

    /**
     * @dev Initializes the contract with the info provided by the developer as the initial operator.
     */
    function initialize(
        address _admin, 
        address _treasury, 
        address _insurance,
        IERC20 usdtAddress,
        uint256 _withdrawalWaitTime,
        uint256 _minimumOrderAmount,
        string memory ppfxVersion
    ) public initializer {
        __ReentrancyGuard_init();
        __Nonces_init();
        __EIP712_init("PPFXCore", ppfxVersion);
        _updateAdmin(_admin);
        _updateTreasury(_treasury);
        _updateInsurance(_insurance);
        _updateUsdt(usdtAddress);
        _updateWithdrawalWaitTime(_withdrawalWaitTime);
        _updateMinimumOrderAmount(_minimumOrderAmount);
    }

    /**
     * @dev Get total trading balance across all available markets.
     */
    function getTradingBalance(address target) external view returns (uint256) {
        return _tradingBalance(target);
    }

    /**
     * @dev Get trading balance in a single market.
     */
    function getTradingBalanceForMarket(address target, string calldata marketName) external view returns (uint256) {
        bytes32 market = _marketHash(marketName);
        return userTradingBalance[target][market];
    }

    /**
     * @dev Get total balance across trading and funding balance.
     */
    function totalBalance(address target) external view returns (uint256) {
        return userFundingBalance[target] + _tradingBalance(target);
    }

    /**
     * @dev Get total number of available markets.
     */
    function totalMarkets() external view returns (uint256) {
        return availableMarkets.length;
    }

    /**
     * @dev Get all available markets.
     */
    function getAllMarkets() external view returns (bytes32[] memory) {
        return availableMarkets;
    }

    /**
     * @dev Get all operator address.
     */
    function getAllOperators() external view returns (address[] memory) {
        return operators.values();
    }

    /**
     * @dev Check if target address is operator.
     */
    function isOperator(address target) external view returns (bool) {
        return operators.contains(target);
    }

    /**
     * @dev Initiate a deposit.
     * @param amount The amount of USDT to deposit
     * 
     * Emits a {UserDeposit} event.
     */
    function deposit(uint256 amount) external nonReentrant {
       _deposit(_msgSender(), _msgSender(), amount);
    }

    /**
     * @dev Initiate a deposit for user.
     * @param user The User to deposit to
     * @param amount The amount of USDT to deposit
     * 
     * Emits a {UserDeposit} event.
     */
    function depositForUser(address user, uint256 amount) external nonReentrant {
        _deposit(_msgSender(), user, amount);
    }

    /**
     * @dev Initiate a withdrawal.
     * @param amount The amount of USDT to withdraw
     *
     * Emits a {UserWithdrawal} event.
     *
     */
    function withdraw(uint256 amount) external nonReentrant {
        _withdraw(_msgSender(), amount);
    }

    /**
     * @dev Initiate a withdrawal for user.
     * @param delegate The delegated address to initiate the withdrawal
     * @param user The target address to withdraw from
     * @param amount The amount of USDT to withdraw
     * @param delegateData Delegate Data from the user
     *
     * Emits a {UserWithdrawal} event.
     *
     */
    function withdrawForUser(address delegate, address user, uint256 amount, DelegateData calldata delegateData) external onlyWithdrawHook nonReentrant {
        (bool valid, address fromUser, address toUser, uint256 sigAmount) = verifyDelegateWithdraw(delegateData);
        require(valid && fromUser == user && toUser == delegate && amount == sigAmount, "Invalid Delegate Data");
        _useNonce(fromUser);
        _withdraw(fromUser, amount);
    }

    /**
     * @dev Claim all pending withdrawal
     * Throw if no available pending withdrawal.
     *
     * Emits a {UserClaimedWithdrawal} event.
     *
     */
    function claimPendingWithdrawal() external nonReentrant {
        _claimPendingWithdrawal(_msgSender(), _msgSender());
    }

    /**
     * @dev Claim all pending withdrawal for target user
     * Throw if no available pending withdrawal / invalid delegate data / signature
     * @param delegate The delegated address to claim pending withdrawal
     * @param user The target address to claim pending withdrawal from
     * @param delegateData Delegate Data from the user
     *
     * Emits a {UserClaimedWithdrawal} event.
     *
     */
    function claimPendingWithdrawalForUser(address delegate, address user, DelegateData calldata delegateData) external onlyWithdrawHook nonReentrant {
        (bool valid, address fromUser, address toUser) = verifyDelegateClaim(delegateData);
        require(valid && fromUser == user && toUser == delegate, "Invalid Delegate Data");
        _useNonce(fromUser);
        _claimPendingWithdrawal(fromUser, delegate);
    }

    /****************************
     * Operators only functions *
     ****************************/

    /**
     * @dev Add Position in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param amount Amount in USDT of the position.
     * @param fee USDT Fee for adding position.
     *
     * Emits a {PositionAdded} event, transfer `amount` and `fee` from funding to trading balance.
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` funding balance must have at least `amount` + `fee`.
     */
    function addPosition(address user, string calldata marketName, uint256 amount, uint256 fee) external onlyOperator {
        _addPosition(user, marketName, amount, fee);
    }

    /**
     * @dev Reduce Position in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param amount Amount in USDT of the position.
     * @param uPNL Unsettled PnL of user position. 
     * @param isProfit Profit or Loss. 
     * @param fee USDT Fee for reducing position.
     *
     * Emits a {PositionReduced} event, transfer `amount` from trading to funding balance,
     * transfer `fee` from contract to treasury account.
     * 
     * Unsettled PNL are credited to user if profit, and deducted if loss.
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `amount` + `fee`.
     * - if `isProfit` is false, `uPNL` must be less than `user` trading balance. 
     */
    function reducePosition(address user, string calldata marketName, uint256 amount, uint256 uPNL, bool isProfit, uint256 fee) external onlyOperator {
        _reducePosition(user, marketName, amount, uPNL, isProfit, fee);
    }

    /**
     * @dev Close Position in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param uPNL Unsettled PnL of user position. 
     * @param isProfit Profit or Loss. 
     * @param fee USDT Fee for closing position.
     *
     * Emits a {PositionReduced} event, trading balance of `marketName` set to 0,
     * transfer `trading balance - fee` to funding balance,
     * transfer `fee` from contract to treasury account. 
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `fee`.
     * - if `isProfit` is false, `uPNL` must be less than `user` trading balance. 
     */
    function closePosition(address user, string calldata marketName, uint256 uPNL, bool isProfit, uint256 fee) external onlyOperator {
        _closePosition(user, marketName, uPNL, isProfit, fee);
    }

    /**
     * @dev Fill order in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param fee USDT Fee for filling order.
     *
     * Emits a {OrderFilled} event, deduct `fee` from trading balance,
     * transfer `fee` from contract to treasury account. 
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `amount` + `fee`.
     */
    function fillOrder(address user, string calldata marketName, uint256 fee) external onlyOperator {
        _fillOrder(user, marketName, fee);
    }

    /**
     * @dev Cancel order in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param amount Amount in USDT of the order.
     * @param fee USDT Fee for cancelling order.
     *
     * Emits a {OrderCancelled} event, transfer `amount` + `fee` from trading to funding balance,
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `amount` + `fee`.
     */
    function cancelOrder(address user, string calldata marketName, uint256 amount, uint256 fee) external onlyOperator {
        _cancelOrder(user, marketName, amount, fee);
    }

    /**
     * @dev Settle given market funding fee for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param amount USDT amount of the funding fee.
     * @param isAdd Adding / Deducting funding fee.
     *
     * Emits a {FundingSettled} event, transfer `amount` from trading to funding balance,
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `amount`.
     */
    function settleFundingFee(address user, string calldata marketName, uint256 amount, bool isAdd) external onlyOperator {
        _settleFundingFee(user, marketName, amount, isAdd);
    }

    /**
     * @dev Liquidate the given market of the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param amount USDT amount of the remaining position.
     * @param fee USDT fee for liquidating.
     *
     * Emits a {Liquidated} event, set trading balance of `marketName` to 0,
     * transfer the remaining `amount` to funding balance,
     * transfer `fee` to insurance account.
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `amount` + `fee`.
     */
    function liquidate(address user, string calldata marketName, uint256 amount, uint256 fee) external onlyOperator {
        _liquidate(user, marketName, amount, fee);
    }

    /**
     * @dev Add collateral to the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param amount USDT amount of the collateral to be added.
     *
     * Emits a {CollateralAdded} event, transfer `amount` from funding to trading balance.
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` funding balance must have at least `amount`.
     */
    function addCollateral(address user, string calldata marketName, uint256 amount) external onlyOperator {
        _addCollateral(user, marketName, amount);
    }

    /**
     * @dev Reduce collateral to the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param amount USDT amount of the collateral to be reduced.
     *
     * Emits a {CollateralDeducted} event, transfer `amount` from trading to funding balance.
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `amount`.
     */
    function reduceCollateral(address user, string calldata marketName, uint256 amount) external onlyOperator {
        _reduceCollateral(user, marketName, amount);
    }

    /**
     * @dev Add new market
     * @param marketName The new market name.
     *
     * Emits a {NewMarketAdded} event.
     *
     * Requirements:
     * - `marketName` must not exists exists in the available markets.
     */
    function addMarket(string calldata marketName) external onlyAdmin() {
        _addMarket(marketName);
    }

    
    /**
     * @dev Bulk Process multiple function calls
     *
     * @param signatures List of encoded selector & args to execute
     *
     */
    function bulkProcessFunctions(
        bytes[] calldata signatures
    ) external onlyOperator {
        uint256 sigLen = signatures.length;
        for (uint256 i = 0; i < sigLen; i++) {
            bytes calldata sig = signatures[i];
            if (sig.length < 4) {
                emit BulkProcessFailedTxInvalidSignature(i, sig);
            } else {
                bytes4 selector = bytes4(sig);
                if (
                    selector == this.addPosition.selector ||
                    selector == this.closePosition.selector || 
                    selector == this.reducePosition.selector ||
                    selector == this.addCollateral.selector ||
                    selector == this.reduceCollateral.selector ||
                    selector == this.fillOrder.selector ||
                    selector == this.cancelOrder.selector ||
                    selector == this.settleFundingFee.selector ||
                    selector == this.liquidate.selector
                ){
                    (bool success, bytes memory data) = address(this).delegatecall(sig);
                    if (!success) {
                        emit BulkProcessFailedTxReverted(i, data);
                    }
                } else {
                    emit BulkProcessFailedTxSelectorNotFound(i, selector);
                }
            }
        }
    }

    /**
     * @dev Accept admin role
     * Emits a {NewAdmin} event.
     *     
     */
     function acceptAdmin() external {
        require(pendingAdmin != address(0), "Admin address can not be zero");
        require(_msgSender() == pendingAdmin, "Caller not pendingAdmin");
        _updateAdmin(pendingAdmin);
        pendingAdmin = address(0);
     }


    /****************************
     * Admin only functions *
     ****************************/

    /**
     * @dev Update Admin account.
     * @param adminAddr The new admin address.     
     * Emits a {TransferAdmin} event.
     * 
     * Requirements:
     * - `adminAddr` cannot be the zero address.
     */
    function transferAdmin(address adminAddr) external onlyAdmin() {
        require(adminAddr != address(0), "Admin address can not be zero");
        _transferAdmin(adminAddr);
    }

    /**
     * @dev Update Treasury account.
     * @param treasuryAddr The new treasury address.
     *
     * Emits a {NewTreasury} event.
     *
     * Requirements:
     * - `treasuryAddr` cannot be the zero address.
     */
    function updateTreasury(address treasuryAddr) external onlyAdmin {
        require(treasuryAddr != address(0), "Treasury address can not be zero");
        _updateTreasury(treasuryAddr);
    }

    /**
     * @dev Add Operator account.
     * @param operatorAddr The new operator address.
     *
     * Emits a {NewOperator} event.
     *
     * Requirements:
     * - `operatorAddr` cannot be the zero address.
     * - `operatorAddr` must not exists in the operators array.
     */
    function addOperator(address operatorAddr) external onlyAdmin {
        require(operatorAddr != address(0), "Operator address can not be zero");
        require(!operators.contains(operatorAddr), "Operator already exists");
        require(operators.length() <= MAX_OPERATORS, "Too many operators");
        _addOperator(operatorAddr);
    }

     /**
     * @dev Remove Operator account.
     * @param operatorAddr The target operator address.
     *
     * Emits a {OperatorRemoved} event.
     *
     * Requirements:
     * - `operatorAddr` cannot be the zero address.
     * - `operatorAddr` must exists in the operators array.
     */
    function removeOperator(address operatorAddr) external onlyAdmin {
        require(operatorAddr != address(0), "Operator address can not be zero");
        require(operators.contains(operatorAddr), "Operator does not exists");
        _removeOperator(operatorAddr);
    }

    /**
     * @dev Remove All Operator accounts.
     *
     * Emits {OperatorRemoved} event for every deleted operator.
     *
     */
    function removeAllOperator() external onlyAdmin {
        require(operators.length() > 0, "No operator found");
        _removeAllOperator();
    }

    /**
     * @dev Update Insurance account.
     * @param insuranceAddr The new insurance address.
     *
     * Emits a {NewInsurance} event.
     *
     * Requirements:
     * - `insuranceAddr` cannot be the zero address.
     */
    function updateInsurance(address insuranceAddr) external onlyAdmin {
        require(insuranceAddr != address(0), "Insurance address can not be zero");
        _updateInsurance(insuranceAddr);
    }

    /**
     * @dev Update USDT token address.
     * @param newUSDT The new USDT address.
     *
     * Emits a {NewUSDT} event.
     *
     * Requirements:
     * - `newUSDT` cannot be the zero address.
     */
    function updateUsdt(address newUSDT) external onlyAdmin {
        require(address(newUSDT) != address(0), "USDT address can not be zero");
        _updateUsdt(IERC20(newUSDT));
    }

    /**
     * @dev Update withdrawal wait time.
     * @param newWaitTime The new withdrawal wait time.
     *
     * Emits a {NewWithdrawalWaitTime} event.
     *
     * Requirements:
     * - `newWaitTime` cannot be zero.
     */
    function updateWithdrawalWaitTime(uint256 newWaitTime) external onlyAdmin {
        require(newWaitTime > 0, "Invalid new wait time");
        _updateWithdrawalWaitTime(newWaitTime);
    }

    /**
     * @dev Update minimum order amount.
     * @param newMinOrderAmt The new minimum order amount.
     *
     * Emits a {NewMinimumOrderAmount} event.
     *
     * Requirements:
     * - `newMinOrderAmt` cannot be zero.
     */
    function updateMinimumOrderAmount(uint256 newMinOrderAmt) external onlyAdmin {
        require(newMinOrderAmt > 0, "Invalid new minimum order amount");
        _updateMinimumOrderAmount(newMinOrderAmt);
    }

    /**
     * @dev Update Withdraw Hook Address.
     * @param newWithdrawHook The new withdraw hook address.
     *
     * Emits a {NewWithdrawHook} event.
     *
     * Requirements:
     * - `newWithdrawHook` cannot be zero address.
     */
    function updateWithdrawHook(address newWithdrawHook) external onlyAdmin {
        require(newWithdrawHook != address(0), "Invalid new withdraw hook address");
        _updateWithdrawHook(newWithdrawHook);
    }

    /****************************
     * Internal functions *
     ****************************/

    function _marketHash(string calldata marketName) internal pure returns (bytes32) {
        return keccak256(bytes(marketName));
    }

    function _tradingBalance(address user) internal view returns (uint256) {
        uint256 balSum = 0;
        uint marketsLen = availableMarkets.length;
        for (uint i = 0; i < marketsLen; i++) {
            balSum += userTradingBalance[user][availableMarkets[i]];
        }
        return balSum;
    }

    function _deductUserTradingBalance(address user, bytes32 market, uint256 amount) internal {
        userTradingBalance[user][market] -= amount;
    }

    function _deductTotalTradingBalance(bytes32 market, uint256 amount) internal {
        totalTradingBalance -= amount;
        marketTotalTradingBalance[market] -= amount;
    }

    function _deductUserFundingBalance(address user, uint256 amount) internal {
        // We are expecting userFundingBalance[user] + pendingWithdrawalBalance[user] >= `amount`,
        // when this function is being called, Subtract funding balance if it is >= `amount`,
        // otherwise, subtract from pending withdrawal balance before subtracting from funding balance.

        // If user's funding balance is sufficient to cover the `amount`
        if (userFundingBalance[user] >= amount) {
            userFundingBalance[user] -= amount;
        } else { // Otherwise we check the pending withdrawal balance

            // Pending withdrawal balance is > `amount`
            if (pendingWithdrawalBalance[user] > amount) {
                // Subtracting `amount` from pending withdrawal balance and
                // reset the withdrawal countdown
                pendingWithdrawalBalance[user] -= amount;
                lastWithdrawalTime[user] = block.timestamp;
                emit WithdrawalBalanceReduced(user, amount);
            } else { // `amount` is >= pending withdrawal balance
                // Clear pending withdrawal balance
                uint256 pendingBal = pendingWithdrawalBalance[user];
                uint256 remaining = amount - pendingBal;
                pendingWithdrawalBalance[user] = 0;
                lastWithdrawalTime[user] = 0;

                // Subtract from funding balance if there is remaining
                if (remaining > 0) {
                    userFundingBalance[user] -= remaining;
                }
                emit WithdrawalBalanceReduced(user, pendingBal);
            }
        }
    }

    function _deposit(address user, address recipient, uint256 amount) internal {
        require(amount > 0, "Invalid amount");
        usdt.safeTransferFrom(user, address(this), amount);
        userFundingBalance[recipient] += amount;
        emit UserDeposit(recipient, amount);
    }

    function _withdraw(address user, uint256 amount) internal {
        require(amount > 0, "Invalid amount");
        require(userFundingBalance[user] >= amount, "Insufficient balance from funding account");
        userFundingBalance[user] -= amount;
        pendingWithdrawalBalance[user] += amount;
        lastWithdrawalTime[user] = block.timestamp;
        emit UserWithdrawal(user, amount, block.timestamp);
    }

    function _claimPendingWithdrawal(address user, address recipient) internal {
        uint256 pendingBal = pendingWithdrawalBalance[user];
        require(pendingBal > 0, "Insufficient pending withdrawal balance");
        require(block.timestamp >= lastWithdrawalTime[user] + withdrawalWaitTime, "No available pending withdrawal to claim");
        usdt.safeTransfer(recipient, pendingBal);
        pendingWithdrawalBalance[user] = 0;
        lastWithdrawalTime[user] = 0;
        emit UserClaimedWithdrawal(user, recipient, pendingBal, block.timestamp);
    }

    function _addUserTradingBalance(address user, bytes32 market, uint256 amount) internal {
        userTradingBalance[user][market] += amount;
        totalTradingBalance += amount;
        marketTotalTradingBalance[market] += amount;
    }

    function _addPosition(address user, string calldata marketName, uint256 amount, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(amount >= minimumOrderAmount, "Position amount is less than minimum order amount");
        uint256 total = amount + fee;
        require(userFundingBalance[user] + pendingWithdrawalBalance[user] >= total, "Insufficient funding balance to add position");

        _deductUserFundingBalance(user, total);
        _addUserTradingBalance(user, market, total);

        emit PositionAdded(user, marketName, amount, fee);
    }

    function _reducePosition(address user, string calldata marketName, uint256 amount, uint256 uPNL, bool isProfit, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(amount >= minimumOrderAmount, "Position amount is less than minimum order amount");

        uint256 total = amount + fee;
        uint256 userTradingBal = userTradingBalance[user][market];

        require(userTradingBal >= total, "Insufficient trading balance to reduce position");

        uint256 newTradingBal = userTradingBal - total;
        if (newTradingBal > 0) {
            require(newTradingBal >= minimumOrderAmount, "New position amount is greater than 0 and less than minimum order amount");
        }

        if (isProfit) {
            // Solvency check
            require(total + uPNL <= marketTotalTradingBalance[market], "uPNL profit will cause market insolvency"); 

            _deductUserTradingBalance(user, market, total);
            _deductTotalTradingBalance(market, total + uPNL);

            userFundingBalance[user] += amount + uPNL;
        } else {
            require(uPNL <= userTradingBal - fee, "Insufficient trading balance to settle uPNL");

            _deductUserTradingBalance(user, market, total);
            _deductTotalTradingBalance(market, total - uPNL);

            userFundingBalance[user] += amount - uPNL;
        }
        usdt.safeTransfer(treasury, fee);
        emit PositionReduced(user, marketName, amount, fee);
    }

    function _closePosition(address user, string calldata marketName, uint256 uPNL, bool isProfit, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        // Make sure its able to subtract fee with user trading balance
        // _reducePosition() will do other checks
        require(userTradingBalance[user][market] >= fee, "Insufficient trading balance to close position");
        _reducePosition(user, marketName, userTradingBalance[user][market] - fee, uPNL, isProfit, fee);
    }

    function _cancelOrder(address user, string calldata marketName, uint256 amount, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        uint256 total = amount + fee;
        require(userTradingBalance[user][market] >= total, "Insufficient trading balance to cancel order");

        userFundingBalance[user] += total;
        _deductUserTradingBalance(user, market, total);
        _deductTotalTradingBalance(market, total);
        
        emit OrderCancelled(user, marketName, amount, fee);
    }

    function _liquidate(address user, string calldata marketName, uint256 amount, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(userTradingBalance[user][market] >= amount + fee, "Insufficient trading balance to liquidate");
        _deductUserTradingBalance(user, market, userTradingBalance[user][market]);
        _deductTotalTradingBalance(market, amount + fee);
        userFundingBalance[user] += amount;
        usdt.safeTransfer(insurance, fee);
        emit Liquidated(user, marketName, amount, fee);
    }

    function _fillOrder(address user, string calldata marketName, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(userTradingBalance[user][market] >= fee, "Insufficient trading balance to pay order filling fee");
        _deductUserTradingBalance(user, market, fee);
        _deductTotalTradingBalance(market, fee);
        usdt.safeTransfer(treasury, fee);
        emit OrderFilled(user, marketName, fee);
    }

    function _settleFundingFee(address user, string calldata marketName, uint256 amount, bool isAdd) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");

        if (isAdd) {
            require(availableFundingFee >= amount, "Insufficient collected funding fee to add funding fee");
            availableFundingFee -= amount;
            userFundingBalance[user] += amount;
        } else {
            require(userTradingBalance[user][market] >= amount, "Insufficient trading balance to deduct funding fee");
            _deductUserTradingBalance(user, market, amount);
            _deductTotalTradingBalance(market, amount);
            availableFundingFee += amount;
        }
        
        emit FundingSettled(user, marketName, amount);
    }

    function _addCollateral(address user, string calldata marketName, uint256 amount) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(userFundingBalance[user] + pendingWithdrawalBalance[user] >= amount, "Insufficient funding balance to add collateral");
        _deductUserFundingBalance(user, amount);
        _addUserTradingBalance(user, market, amount);
        emit CollateralAdded(user, marketName, amount);
    }

    function _reduceCollateral(address user, string calldata marketName, uint256 amount) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(userTradingBalance[user][market] >= amount, "Insufficient trading balance to reduce collateral");
        _deductUserTradingBalance(user, market, amount);
        _deductTotalTradingBalance(market, amount);
        userFundingBalance[user] += amount;
        emit CollateralDeducted(user, marketName, amount);
    }

    function _addMarket(string calldata marketName) internal {
        bytes32 market = _marketHash(marketName);
        require(!marketExists[market], "Market already exists");
        availableMarkets.push(market);
        marketExists[market] = true;
        emit NewMarketAdded(market, marketName);
    }

    function _transferAdmin(address adminAddr) internal {
        pendingAdmin = adminAddr;
        emit TransferAdmin(adminAddr);
    }

    function _updateAdmin(address adminAddr) internal {
        admin = adminAddr;
        emit NewAdmin(adminAddr);
    }

    function _updateTreasury(address treasuryAddr) internal {
        treasury = treasuryAddr;
        emit NewTreasury(treasuryAddr);
    }

    function _removeAllOperator() internal {
        address[] memory operatorList = operators.values();
        uint operatorLen = operatorList.length;
        for (uint i = 0; i < operatorLen; i++) {
            address operatorToBeRemoved = operatorList[i];
            operators.remove(operatorToBeRemoved);
            emit OperatorRemoved(operatorToBeRemoved);
        }
    }

    function _removeOperator(address operatorAddr) internal {
        operators.remove(operatorAddr);
        emit OperatorRemoved(operatorAddr);
    }

    function _addOperator(address operatorAddr) internal {
        operators.add(operatorAddr);
        emit NewOperator(operatorAddr);
    }

    function _updateInsurance(address insuranceAddr) internal {
        insurance = insuranceAddr;
        emit NewInsurance(insuranceAddr);
    }

    function _updateWithdrawHook(address withdrawHookAddr) internal {
        withdrawHook = withdrawHookAddr;
        emit NewWithdrawHook(withdrawHookAddr);
    }

    function _updateUsdt(IERC20 newUSDT) internal {
        usdt = newUSDT;
        emit NewUSDT(address(newUSDT));
    }

    function _updateWithdrawalWaitTime(uint256 newBlockTime) internal {
        withdrawalWaitTime = newBlockTime;
        emit NewWithdrawalWaitTime(newBlockTime);
    }

    function _updateMinimumOrderAmount(uint256 newMinOrderAmt) internal {
        minimumOrderAmount = newMinOrderAmt;
        emit NewMinimumOrderAmount(newMinOrderAmt);
    }
    
    /*******************************************************************
     * Functions for getting hash data to sign & validating signatures *
     *******************************************************************/

    function getWithdrawHash(
        address user,
        address delegate,
        uint256 amount,
        uint48 deadline
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    WITHDRAW_FOR_USER_TYPEHASH,
                    delegate,
                    user,
                    amount,
                    nonces(user),
                    deadline
                )
            )
        );
    }

    function getClaimHash(
        address user,
        address delegate,
        uint48 deadline
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CLAIM_FOR_USER_TYPEHASH,
                    delegate,
                    user,
                    nonces(user),
                    deadline
                )
            )
        );
    }

    function verifyDelegateWithdraw(DelegateData calldata data) public view returns (bool, address, address, uint256){
        (address signer, address delegate, uint256 amount, bool active, bool signerMatch) = _validateDelegateWithdraw(data);
        return (signerMatch && active, signer, delegate, amount);
    }

    function verifyDelegateClaim(DelegateData calldata data) public view returns (bool, address, address){
        (address signer, address delegate, bool active, bool signerMatch) = _validateDelegateClaim(data);
        return (signerMatch && active, signer, delegate);
    }

    /***********************************************
     * Internal Functions for validating signature *
     ***********************************************/

    function _validateDelegateWithdraw(
        DelegateData calldata data
    ) internal view returns (address signer, address delegate, uint256 amount, bool active, bool signerMatch) {
        (bool isValid, address recovered) = _recoverWithdrawDelegateDataSigner(data);
        return (
            recovered,
            data.delegate,
            data.amount,
            data.deadline >= block.timestamp,
            isValid && recovered == data.from
        );
    }

    function _validateDelegateClaim(
        DelegateData calldata data
    ) internal view returns (address signer, address delegate, bool active, bool signerMatch) {
        (bool isValid, address recovered) = _recoverClaimDelegateDataSigner(data);
        return (
            recovered,
            data.delegate,
            data.deadline >= block.timestamp,
            isValid && recovered == data.from
        );
    }

    function _recoverWithdrawDelegateDataSigner(
        DelegateData calldata data
    ) internal view virtual returns (bool, address) {
        (address recovered, ECDSA.RecoverError err, ) = getWithdrawHash(
            data.from,
            data.delegate,
            data.amount,
            data.deadline
        ).tryRecover(data.signature);

        return (err == ECDSA.RecoverError.NoError, recovered);
    }

    function _recoverClaimDelegateDataSigner(
        DelegateData calldata data
    ) internal view virtual returns (bool, address) {
        (address recovered, ECDSA.RecoverError err, ) = getClaimHash(
            data.from,
            data.delegate,
            data.deadline
        ).tryRecover(data.signature);

        return (err == ECDSA.RecoverError.NoError, recovered);
    }
}
