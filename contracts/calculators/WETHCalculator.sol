// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../SodaMaster.sol";
import "./ICalculator.sol";

// This calculator fitures out lending SoETH by depositing WETH.
// All the money are still managed by the pool, but the calculator tells him
// what to do.
// This contract is owned by Timelock.
contract WETHCalculator is Ownable, ICalculator {
    using SafeMath for uint256;

    uint256 constant RATE_BASE = 1e6;
    uint256 constant LTV_BASE = 100;

    SodaMaster public sodaMaster;

    uint256 public override rate;  // Daily interest rate, a number between 0 and 10000.
    uint256 public override minimumLTV;  // Minimum Loan-to-value ratio, a number between 10 and 90.
    uint256 public override maximumLTV;  // Maximum Loan-to-value ratio, a number between 15 and 95.

    // We will start with rate = 500, which means 0.05% daily interest.
    // We will initially set _minimumLTV as 90, and maximumLTV as 95.
    // It should work perfectly, however, we may change it based on governance.
    // The maximum daily interest is 1%, and maximumLTV - _minimumLTV >= 5.
    // As a result, user has at least 5 days to do something.

    // Info of each loan.
    struct LoanInfo {
        address who;  // The user that creats the loan.
        uint256 amount;  // How many SoETH tokens the user has lended.
        uint256 lockedAmount;  // How many WETH tokens the user has locked.
        uint256 time;  // When the loan is created or updated.
        uint256 rate;  // At what daily interest rate the user lended.
        uint256 minimumLTV;  // At what minimum loan-to-deposit ratio the user lended.
        uint256 maximumLTV;  // At what maximum loan-to-deposit ratio the user lended.
    }

    mapping (uint256 => LoanInfo) public loanInfo;  // loanId => LoanInfo
    uint256 private nextLoanId;

    constructor(SodaMaster _sodaMaster) public {
        sodaMaster = _sodaMaster;
    }

    // Change the bank's interest rate and LTVs.
    // Can only be called by the owner.
    // The change should only affect loans made after it.
    function changRateAndLTV(uint256 _rate, uint256 _minimumLTV, uint256 _maximumLTV) public onlyOwner {
        require(_rate <= RATE_BASE, "_rate <= RATE_BASE");
        require(_minimumLTV + 5 <= _maximumLTV, "+ 5 <= _maximumLTV");
        require(_minimumLTV >= 10, ">= 10");
        require(_maximumLTV <= 95, "<= 95");

        rate = _rate;
        minimumLTV = _minimumLTV;
        maximumLTV = _maximumLTV;
    }

    /**
     * @dev See {ICalculator-getNextLoanId}.
     */
    function getNextLoanId() external view override returns(uint256) {
        return nextLoanId;
    }

    /**
     * @dev See {ICalculator-getLoanCreator}.
     */
    function getLoanCreator(uint256 _loanId) external view override returns (address) {
        return loanInfo[_loanId].who;
    }

    /**
     * @dev See {ICalculator-getLoanPrincipal}.
     */
    function getLoanPrincipal(uint256 _loanId) public view override returns (uint256) {
        return loanInfo[_loanId].amount;
    }

    /**
     * @dev See {ICalculator-getLoanPrincipal}.
     */
    function getLoanInterest(uint256 _loanId) public view override returns (uint256) {
        uint256 principal = loanInfo[_loanId].amount;
        uint256 durationByDays = now.sub(loanInfo[_loanId].time) / (1 days) + 1;
        if (durationByDays == 0) {
            return 0;
        }

        uint256 interest = loanInfo[_loanId].amount.mul(loanInfo[_loanId].rate).div(RATE_BASE).mul(durationByDays);
        uint256 lockedAmount = loanInfo[_loanId].lockedAmount;
        uint256 maximumAmount = lockedAmount.mul(loanInfo[_loanId].maximumLTV).div(LTV_BASE);

        // Interest has a cap. After that collector will collect.
        if (principal + interest <= maximumAmount) {
            return interest;
        } else {
            return maximumAmount - principal;
        }
    }

    /**
     * @dev See {ICalculator-getLoanTotal}.
     */
    function getLoanTotal(uint256 _loanId) public view override returns (uint256) {
        return getLoanPrincipal(_loanId) + getLoanInterest(_loanId);
    }

    /**
     * @dev See {ICalculator-getLoanExtra}.
     */
    function getLoanExtra(uint256 _loanId) external view override returns (uint256) {
        uint256 lockedAmount = loanInfo[_loanId].lockedAmount;
        uint256 maximumAmount = lockedAmount.mul(loanInfo[_loanId].maximumLTV).div(LTV_BASE);
        require(lockedAmount >= maximumAmount, "getLoanExtra: >=");
        return (lockedAmount - maximumAmount) / 2;
    }

    /**
     * @dev See {ICalculator-getLoanLockedAmount}.
     */
    function getLoanLockedAmount(uint256 _loanId) external view override returns (uint256) {
        return loanInfo[_loanId].lockedAmount;
    }

    /**
     * @dev See {ICalculator-getLoanTime}.
     */
    function getLoanTime(uint256 _loanId) external view override returns (uint256) {
        return loanInfo[_loanId].time;
    }

    /**
     * @dev See {ICalculator-getLoanRate}.
     */
    function getLoanRate(uint256 _loanId) external view override returns (uint256) {
        return loanInfo[_loanId].rate;
    }

    /**
     * @dev See {ICalculator-getLoanMinimumLTV}.
     */
    function getLoanMinimumLTV(uint256 _loanId) external view override returns (uint256) {
        return loanInfo[_loanId].minimumLTV;
    }

    /**
     * @dev See {ICalculator-getLoanMaximumLTV}.
     */
    function getLoanMaximumLTV(uint256 _loanId) external view override returns (uint256) {
        return loanInfo[_loanId].maximumLTV;
    }

    /**
     * @dev See {ICalculator-borrow}.
     */
    function borrow(address _who, uint256 _amount) external override {
        require(msg.sender == sodaMaster.bank(), "sender not bank");

        uint256 lockedAmount = _amount.mul(LTV_BASE).div(minimumLTV);
        require(lockedAmount >= 1, "lock at least 1 WETH");

        loanInfo[nextLoanId].who = _who;
        loanInfo[nextLoanId].amount = _amount;
        loanInfo[nextLoanId].lockedAmount = lockedAmount;
        loanInfo[nextLoanId].time = now;
        loanInfo[nextLoanId].rate = rate;
        loanInfo[nextLoanId].minimumLTV = minimumLTV;
        loanInfo[nextLoanId].maximumLTV = maximumLTV;
        ++nextLoanId;
    }

    /**
     * @dev See {ICalculator-payBackInFull}.
     */
    function payBackInFull(uint256 _loanId) external override {
        require(msg.sender == sodaMaster.bank(), "sender not bank");

        loanInfo[_loanId].amount = 0;
        loanInfo[_loanId].lockedAmount = 0;

        loanInfo[_loanId].time = now;
    }

    /**
     * @dev See {ICalculator-collectDebt}.
     */
    function collectDebt(uint256 _loanId) external override {
        require(msg.sender == sodaMaster.bank(), "sender not bank");

        uint256 loanTotal = getLoanTotal(_loanId);
        uint256 maximumLoan = loanInfo[_loanId].amount.mul(loanInfo[_loanId].maximumLTV).div(LTV_BASE);

        // You can collect only if the user defaults.
        require(loanTotal >= maximumLoan, "collectDebt: >=");

        // Now the debt is clear. SodaPool, please do the rest.
        loanInfo[_loanId].amount = 0;
        loanInfo[_loanId].lockedAmount = 0;
        loanInfo[_loanId].time = now;
    }
}
