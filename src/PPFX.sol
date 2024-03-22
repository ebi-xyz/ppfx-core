// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPPFX} from "./IPPFX.sol";

contract PPFX is IPPFX, Context {

    uint256 constant public MAX_UINT256 = 2**256 - 1;

    bytes4 constant public ADD_POSITION_SELECTOR = 0xa54efd84; // bytes4(keccak256("addPosition(address,string,uint256,uint256)"))
    bytes4 constant public REDUCE_POSITION_SELECTOR = 0x0e23f3d1; // bytes4(keccak256("reducePosition(address,string,uint256,uint256)"))
    bytes4 constant public CLOSE_POSITION_SELECTOR = 0x29228a43; // bytes4(keccak256("closePosition(address,string,uint256,uint256)"))
    bytes4 constant public CANCEL_ORDER_SELECTOR = 0x17a0b3e0; // bytes4(keccak256("cancelOrder(address,string,uint256,uint256)"))
    bytes4 constant public LIQUIDATE_SELECTOR = 0xdd5273dc; // bytes4(keccak256("liquidate(address,string,uint256,uint256)"))

    bytes4 constant public FILL_ORDER_SELECTOR = 0x21c5aa45; // bytes4(keccak256("fillOrder(address,string,uint256)"))
    bytes4 constant public SETTLE_FUNDING_SELECTOR = 0x394d3159; // bytes4(keccak256("settleFundingFee(address,string,uint256)"))
    bytes4 constant public ADD_COLLATERAL_SELECTOR = 0x0c086c2d; // bytes4(keccak256("addCollateral(address,string,uint256)"))
    bytes4 constant public REDUCE_COLLATERAL_SELECTOR = 0xcec57775; // bytes4(keccak256("reduceCollateral(address,string,uint256)"))

    error FunctionSelectorNotFound(bytes4 methodID);

    using Math for uint256;
    using SafeERC20 for IERC20;

    address public treasury;
    address public admin;
    address public operator;
    address public insurance;

    IERC20 public usdt;

    uint256 public withdrawalWaitTime;
    uint256 public totalTradingBalance;

    uint256 public availableFundingFee;

    mapping(bytes32 => uint256) public marketTotalTradingBalance;
    mapping(address => mapping(bytes32 => uint256)) public userTradingBalance;
    mapping(address => uint256) public userFundingBalance;

    mapping(address => uint256) public pendingWithdrawalBalance;
    mapping(address => uint256) public lastWithdrawalBlock;

    mapping(bytes32 => bool) public marketExists;
    bytes32[] public availableMarkets;

    /**
     * @dev Throws if called by any accoutn other than the Admin
     */
    modifier onlyAdmin {
        require(_msgSender() == admin, "Caller not admin");
        _;
    }

    /**
     * @dev Throws if called by any accoutn other than the Operator
     */
    modifier onlyOperator {
        require(_msgSender() == operator, "Caller not operator");
        _;
    }

    /**
     * @dev Initializes the contract with the info provided by the developer as the initial operator.
     */
    constructor(
        address _admin, 
        address _treasury, 
        address _insurance, 
        IERC20 usdtAddress,
        uint256 _withdrawalWaitTime
    ) {
        _updateAdmin(_admin);
        _updateTreasury(_treasury);
        _updateInsurance(_insurance);
        _updateOperator(_msgSender());
        _updateUsdt(usdtAddress);
        _updateWithdrawalWaitTime(_withdrawalWaitTime);
    }

    /**
     * @dev Get target address funding balance.
     * @return Target's funding balance.
     */
    function fundingBalance(address target) external view returns (uint256) {
        return _fundingBalance(target);
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
    function getTradingBalanceForMarket(address target, string memory marketName) external view returns (uint256) {
        bytes32 market = _marketHash(marketName);
        return userTradingBalance[target][market];
    }

    /**
     * @dev Get total balance across trading and funding balance.
     */
    function totalBalance(address target) external view returns (uint256) {
        return _fundingBalance(target) + _tradingBalance(target);
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
     * @dev Initiate a deposit.
     * @param amount The amount of USDT to deposit
     * 
     * Emits a {UserDeposit} event.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(usdt.allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");
        usdt.safeTransferFrom(_msgSender(), address(this), amount);
        userFundingBalance[_msgSender()] += amount;
        emit UserDeposit(_msgSender(), amount);
    }

    /**
     * @dev Initiate a withdrawal.
     * @param amount The amount of USDT to withdraw
     *
     * Emits a {UserWithdrawal} event.
     *
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(_fundingBalance(_msgSender()) >= amount, "Insufficient balance from funding account");
        userFundingBalance[_msgSender()] -= amount;
        pendingWithdrawalBalance[_msgSender()] += amount;
        lastWithdrawalBlock[_msgSender()] = block.number;
        emit UserWithdrawal(_msgSender(), amount, block.number + withdrawalWaitTime);
    }

    /**
     * @dev Claim all pending withdrawal
     * Throw if no available pending withdrawal.
     *
     * Emits a {UserClaimedWithdrawal} event.
     *
     */
    function claimPendingWithdrawal() external {
        require(pendingWithdrawalBalance[_msgSender()] > 0, "Insufficient pending withdrawal balance");
        require(block.number >= lastWithdrawalBlock[_msgSender()] + withdrawalWaitTime, "No available pending withdrawal to claim");
        usdt.safeTransfer(_msgSender(), pendingWithdrawalBalance[_msgSender()]);
        uint256 withdrew = pendingWithdrawalBalance[_msgSender()];
        pendingWithdrawalBalance[_msgSender()] = 0;
        lastWithdrawalBlock[_msgSender()] = 0;
        emit UserClaimedWithdrawal(_msgSender(), withdrew, block.number);
    }

    /****************************
     * Operators only functions *
     ****************************/

    /**
     * @dev Add Position in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param size Size in USDT of the position.
     * @param fee USDT Fee for adding position.
     *
     * Emits a {PositionAdded} event, transfer `size` and `fee` from funding to trading balance.
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` funding balance must have at least `size` + `fee`.
     */
    function addPosition(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator {
        _addPosition(user, marketName, size, fee);
    }

    /**
     * @dev Reduce Position in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param size Size in USDT of the position.
     * @param uPNL Unsettled PnL of user position. 
     * @param isProfit Profit or Loss. 
     * @param fee USDT Fee for reducing position.
     *
     * Emits a {PositionReduced} event, transfer `size` from trading to funding balance,
     * transfer `fee` from contract to treasury account.
     * 
     * Unsettled PNL are credited to user if profit, and deducted if loss.
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `size` + `fee`.
     * - if `isProfit` is false, `uPNL` must be less than `user` trading balance. 
     */
    function reducePosition(address user, string memory marketName, uint256 size, uint256 uPNL, bool isProfit, uint256 fee) external onlyOperator {
        _reducePosition(user, marketName, size, uPNL, isProfit, fee);
    }

    /**
     * @dev Close Position in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param uPNL Unsettled PnL of user position. 
     * @param isProfit Profit or Loss. 
     * @param fee USDT Fee for closing position.
     *
     * Emits a {PositionClosed} event, trading balance of `marketName` set to 0,
     * transfer `trading balance - fee` to funding balance,
     * transfer `fee` from contract to treasury account. 
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `fee`.
     * - if `isProfit` is false, `uPNL` must be less than `user` trading balance. 
     */
    function closePosition(address user, string memory marketName, uint256 uPNL, bool isProfit, uint256 fee) external onlyOperator {
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
     * - `user` trading balance must have at least `size` + `fee`.
     */
    function fillOrder(address user, string memory marketName, uint256 fee) external onlyOperator {
        _fillOrder(user, marketName, fee);
    }

    /**
     * @dev Cancel order in the given market for the given user.
     * @param user The target user account.
     * @param marketName The target market name.
     * @param size Size in USDT of the order.
     * @param fee USDT Fee for cancelling order.
     *
     * Emits a {OrderCancelled} event, transfer `size` + `fee` from trading to funding balance,
     *
     * Requirements:
     * - `marketName` must exists
     * - `user` trading balance must have at least `size` + `fee`.
     */
    function cancelOrder(address user, string memory marketName, uint256 size, uint256 fee) external onlyOperator {
        _cancelOrder(user, marketName, size, fee);
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
    function settleFundingFee(address user, string memory marketName, uint256 amount, bool isAdd) external onlyOperator {
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
    function liquidate(address user, string memory marketName, uint256 amount, uint256 fee) external onlyOperator {
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
    function addCollateral(address user, string memory marketName, uint256 amount) external onlyOperator {
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
    function reduceCollateral(address user, string memory marketName, uint256 amount) external onlyOperator {
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
    function addMarket(string memory marketName) external onlyAdmin() {
        _addMarket(marketName);
    }

    
    /**
     * @dev Bulk Process multiple function calls that with fee parameters, 
     * addPosition, reducePosition, closePosition, cancelOrder and liquidate
     *
     * @param bulkStructs List of BulkStruct to execute
     *
     */
    function bulkProcessFunctionsWithFee(
        BulkStruct[] memory bulkStructs
    ) external onlyOperator {
        for (uint256 i = 0; i < bulkStructs.length; i++) {
            if (bulkStructs[i].methodID == ADD_POSITION_SELECTOR) {
                _addPosition(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount, bulkStructs[i].fee);
            } else if (bulkStructs[i].methodID == REDUCE_POSITION_SELECTOR) {
                _reducePosition(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount, bulkStructs[i].uPNL, bulkStructs[i].isProfit, bulkStructs[i].fee);
            } else if (bulkStructs[i].methodID == CLOSE_POSITION_SELECTOR) {
                _closePosition(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].uPNL, bulkStructs[i].isProfit, bulkStructs[i].fee);
            } else if (bulkStructs[i].methodID == CANCEL_ORDER_SELECTOR) {
                _cancelOrder(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount, bulkStructs[i].fee);
            } else if (bulkStructs[i].methodID == LIQUIDATE_SELECTOR) {
                _liquidate(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount, bulkStructs[i].fee);
            } else {
                revert FunctionSelectorNotFound({
                    methodID: bulkStructs[i].methodID
                });
            }
        }
    }

    /**
     * @dev Bulk Process multiple function calls that without fee parameters, 
     * fillOrder, settleFundingFee, addCollateral, reduceCollateral
     *
     * @param bulkStructs List of BulkStruct to execute
     *
     */
    function bulkProcessFunctionsWithoutFee(
        BulkStruct[] memory bulkStructs
    ) external onlyOperator {
        for (uint256 i = 0; i < bulkStructs.length; i++) {
            if (bulkStructs[i].methodID == FILL_ORDER_SELECTOR) {
                _fillOrder(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount);
            } else if (bulkStructs[i].methodID == SETTLE_FUNDING_SELECTOR) {
                _settleFundingFee(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount, bulkStructs[i].isAdd);
            } else if (bulkStructs[i].methodID == ADD_COLLATERAL_SELECTOR) {
                _addCollateral(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount);
            } else if (bulkStructs[i].methodID == REDUCE_COLLATERAL_SELECTOR) {
                _reduceCollateral(bulkStructs[i].user, bulkStructs[i].marketName, bulkStructs[i].amount);
            } else {
                revert FunctionSelectorNotFound({
                    methodID: bulkStructs[i].methodID
                });
            }
        }
    }

    /****************************
     * Admin only functions *
     ****************************/

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
     * @dev Update Operator account.
     * @param operatorAddr The new treasury address.
     *
     * Emits a {NewOperator} event.
     *
     * Requirements:
     * - `operatorAddr` cannot be the zero address.
     */
    function updateOperator(address operatorAddr) external onlyAdmin {
        require(operatorAddr != address(0), "Operator address can not be zero");
        _updateOperator(operatorAddr);
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
     * @param newBlockTime The new withdrawal wait time.
     *
     * Emits a {NewWithdrawalWaitTime} event.
     *
     * Requirements:
     * - `newBlockTime` cannot be zero.
     */
    function updateWithdrawalWaitTime(uint256 newBlockTime) external onlyAdmin {
        require(newBlockTime > 0, "Invalid new block time");
        _updateWithdrawalWaitTime(newBlockTime);
    }

    /****************************
     * Internal functions *
     ****************************/

    function _marketHash(string memory marketName) internal pure returns (bytes32) {
        return keccak256(abi.encode(marketName));
    }

    function _tradingBalance(address user) internal view returns (uint256) {
        uint256 balSum = 0;
        for (uint i = 0; i < availableMarkets.length; i++) {
            balSum += userTradingBalance[user][availableMarkets[i]];
        }
        return balSum;
    }

    function _fundingBalance(address user) internal view returns (uint256) {
        return userFundingBalance[user];
    }

    function _deductUserTradingBalance(address user, bytes32 market, uint256 amount) internal {
        userTradingBalance[user][market] -= amount;
        totalTradingBalance -= amount;
        marketTotalTradingBalance[market] -= amount;
    }

    function _addUserTradingBalance(address user, bytes32 market, uint256 amount) internal {
        userTradingBalance[user][market] += amount;
        totalTradingBalance += amount;
        marketTotalTradingBalance[market] += amount;
    }

    function _addPosition(address user, string memory marketName, uint256 size, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        uint256 total = size + fee;
        require(_fundingBalance(user) >= total, "Insufficient funding balance to add position");

        userFundingBalance[user] -= total;
        _addUserTradingBalance(user, market, total);

        emit PositionAdded(user, marketName, size, fee);
    }

    function _reducePosition(address user, string memory marketName, uint256 size, uint256 uPNL, bool isProfit, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        uint256 total = size + fee;
        require(userTradingBalance[user][market] >= total, "Insufficient trading balance to reduce position");

        if (isProfit == true) {
            // Solvency check
            require(uPNL <= marketTotalTradingBalance[market], "uPNL profit will cause market insolvency"); 

            _deductUserTradingBalance(user, market, total);
            userFundingBalance[user] += size + uPNL;
        } else {
            require(uPNL <= userTradingBalance[user][market] - fee, "Insufficient trading balance to settle uPNL");

            _deductUserTradingBalance(user, market, total);
            userFundingBalance[user] += size - uPNL;
        }

        usdt.safeTransfer(treasury, fee);
        emit PositionReduced(user, marketName, size, fee);
    }

    // TODO: refactor to call _reducePosition?
    function _closePosition(address user, string memory marketName, uint256 uPNL, bool isProfit, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(userTradingBalance[user][market] >= fee, "Insufficient trading balance to pay fee and close position");
        uint256 size = userTradingBalance[user][market] - fee;

        if (isProfit == true) {
            // Solvency check
            require(uPNL <= marketTotalTradingBalance[market], "uPNL profit will cause market insolvency"); 

            _deductUserTradingBalance(user, market, userTradingBalance[user][market]);
            userFundingBalance[user] += size + uPNL;
        } else {
            require(uPNL <= userTradingBalance[user][market] - fee, "Insufficient trading balance to settle uPNL");

            _deductUserTradingBalance(user, market, userTradingBalance[user][market]);
            userFundingBalance[user] += size - uPNL;
        }

        usdt.safeTransfer(treasury, fee);
        emit PositionReduced(user, marketName, size, fee);
    }

    function _cancelOrder(address user, string memory marketName, uint256 size, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        uint256 total = size + fee;
        require(userTradingBalance[user][market] >= total, "Insufficient trading balance to cancel order");

        userFundingBalance[user] += total;
        _deductUserTradingBalance(user, market, total);
        
        emit OrderCancelled(user, marketName, size, fee);
    }

    function _liquidate(address user, string memory marketName, uint256 amount, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        uint256 total = amount + fee;
        uint256 userTradingBal = userTradingBalance[user][market];
        require(userTradingBal >= total, "Trading balance must be larger than total amount to liquidate");

        _deductUserTradingBalance(user, market, userTradingBal);

        uint256 remaining = userTradingBal - total;
        userFundingBalance[user] += remaining;

        usdt.safeTransfer(insurance, fee);
        emit Liquidated(user, marketName, amount, fee);
    }

    function _fillOrder(address user, string memory marketName, uint256 fee) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(userTradingBalance[user][market] >= fee, "Insufficient trading balance to pay order filling fee");
        _deductUserTradingBalance(user, market, fee);
        usdt.safeTransfer(treasury, fee);
        emit OrderFilled(user, marketName, fee);
    }

    function _settleFundingFee(address user, string memory marketName, uint256 amount, bool isAdd) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");

        if (isAdd) {
            require(availableFundingFee >= amount, "Insufficient collected funding fee to add funding fee");
            userFundingBalance[user] += amount;
            availableFundingFee -= amount;
        } else {
            require(userTradingBalance[user][market] >= amount, "Insufficient trading balance to deduct funding fee");
            _deductUserTradingBalance(user, market, amount);
            availableFundingFee += amount;
        }
        
        emit FundingSettled(user, marketName, amount);
    }

    function _addCollateral(address user, string memory marketName, uint256 amount) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(_fundingBalance(user) >= amount, "Insufficient funding balance to add collateral");
        userFundingBalance[user] -= amount;
        _addUserTradingBalance(user, market, amount);
        emit CollateralAdded(user, marketName, amount);
    }

    function _reduceCollateral(address user, string memory marketName, uint256 amount) internal {
        bytes32 market = _marketHash(marketName);
        require(marketExists[market], "Provided market does not exists");
        require(userTradingBalance[user][market] >= amount, "Insufficient trading balance to reduce collateral");
        _deductUserTradingBalance(user, market, amount);
        userFundingBalance[user] += amount;
        emit CollateralDeducted(user, marketName, amount);
    }

    function _addMarket(string memory marketName) internal {
        bytes32 market = _marketHash(marketName);
        require(!marketExists[market], "Market already exists");
        availableMarkets.push(market);
        marketExists[market] = true;
        emit NewMarketAdded(market, marketName);
    }

    function _updateAdmin(address adminAddr) internal {
        require(adminAddr != address(0), "Admin address can not be zero");
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
