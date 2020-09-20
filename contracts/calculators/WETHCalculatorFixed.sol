// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../SodaMaster.sol";
import "./ICalculator.sol";
import "./WETHCalculator.sol";

// This calculator fitures out lending SoETH by depositing WETH.
// All the money are still managed by the pool, but the calculator tells him
// what to do.
// This contract is owned by Timelock.
contract WETHCalculatorFixed is Ownable, ICalculator {
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
        bool filledByOld;
    }

    mapping (uint256 => LoanInfo) private loanInfoFixed;  // loanId => LoanInfo
    uint256 private nextLoanId;

    WETHCalculator public oldCalculator;

    uint256 constant LOAN_ID_START = 1e18;

    constructor(SodaMaster _sodaMaster, WETHCalculator _oldCalculator) public {
        sodaMaster = _sodaMaster;
        oldCalculator = _oldCalculator;

        // Start loanId from a large enough number.
        nextLoanId = LOAN_ID_START;
    }

    function loanInfo(uint256 _loanId) public returns (address, uint256, uint256, uint256, uint256, uint256, uint256) {
      if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
        return oldCalculator.loanInfo(_loanId);
      } else {
        address who = loanInfoFixed[nextLoanId].who;
        uint256 amount = loanInfoFixed[nextLoanId].amount;
        uint256 lockedAmount = loanInfoFixed[nextLoanId].lockedAmount;
        uint256 time = loanInfoFixed[nextLoanId].time;
        uint256 rate = loanInfoFixed[nextLoanId].rate;
        uint256 minimumLTV = loanInfoFixed[nextLoanId].minimumLTV;
        uint256 maximumLTV = loanInfoFixed[nextLoanId].maximumLTV;
        return (who, amount, lockedAmount, time, rate, minimumLTV, maximumLTV);
      }
    }

    // Change the bank's interest rate and LTVs.
    // Can only be called by the owner.
    // The change should only affect loans made after it.
    function changeRateAndLTV(uint256 _rate, uint256 _minimumLTV, uint256 _maximumLTV) public onlyOwner {
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
        if (_loanId < LOAN_ID_START  && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanCreator(_loanId);
        }

        return loanInfoFixed[_loanId].who;
    }

    /**
     * @dev See {ICalculator-getLoanPrincipal}.
     */
    function getLoanPrincipal(uint256 _loanId) public view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanPrincipal(_loanId);
        }

        return loanInfoFixed[_loanId].amount;
    }

    /**
     * @dev See {ICalculator-getLoanPrincipal}.
     */
    function getLoanInterest(uint256 _loanId) public view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanInterest(_loanId);
        }

        uint256 principal = loanInfoFixed[_loanId].amount;
        uint256 durationByDays = now.sub(loanInfoFixed[_loanId].time) / (1 days) + 1;

        uint256 interest = loanInfoFixed[_loanId].amount.mul(loanInfoFixed[_loanId].rate).div(RATE_BASE).mul(durationByDays);
        uint256 lockedAmount = loanInfoFixed[_loanId].lockedAmount;
        uint256 maximumAmount = lockedAmount.mul(loanInfoFixed[_loanId].maximumLTV).div(LTV_BASE);

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
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanTotal(_loanId);
        }

        return getLoanPrincipal(_loanId) + getLoanInterest(_loanId);
    }

    /**
     * @dev See {ICalculator-getLoanExtra}.
     */
    function getLoanExtra(uint256 _loanId) external view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanExtra(_loanId);
        }

        uint256 lockedAmount = loanInfoFixed[_loanId].lockedAmount;
        uint256 maximumAmount = lockedAmount.mul(loanInfoFixed[_loanId].maximumLTV).div(LTV_BASE);
        require(lockedAmount >= maximumAmount, "getLoanExtra: >=");
        return (lockedAmount - maximumAmount) / 2;
    }

    /**
     * @dev See {ICalculator-getLoanLockedAmount}.
     */
    function getLoanLockedAmount(uint256 _loanId) external view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanLockedAmount(_loanId);
        }

        return loanInfoFixed[_loanId].lockedAmount;
    }

    /**
     * @dev See {ICalculator-getLoanTime}.
     */
    function getLoanTime(uint256 _loanId) external view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanTime(_loanId);
        }

        return loanInfoFixed[_loanId].time;
    }

    /**
     * @dev See {ICalculator-getLoanRate}.
     */
    function getLoanRate(uint256 _loanId) external view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanRate(_loanId);
        }

        return loanInfoFixed[_loanId].rate;
    }

    /**
     * @dev See {ICalculator-getLoanMinimumLTV}.
     */
    function getLoanMinimumLTV(uint256 _loanId) external view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanMinimumLTV(_loanId);
        }

        return loanInfoFixed[_loanId].minimumLTV;
    }

    /**
     * @dev See {ICalculator-getLoanMaximumLTV}.
     */
    function getLoanMaximumLTV(uint256 _loanId) external view override returns (uint256) {
        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            return oldCalculator.getLoanMaximumLTV(_loanId);
        }

        return loanInfoFixed[_loanId].maximumLTV;
    }

    /**
     * @dev See {ICalculator-borrow}.
     */
    function borrow(address _who, uint256 _amount) external override {
        require(msg.sender == sodaMaster.bank(), "sender not bank");

        uint256 lockedAmount = _amount.mul(LTV_BASE).div(minimumLTV);
        require(lockedAmount >= 1, "lock at least 1 WETH");

        loanInfoFixed[nextLoanId].who = _who;
        loanInfoFixed[nextLoanId].amount = _amount;
        loanInfoFixed[nextLoanId].lockedAmount = lockedAmount;
        loanInfoFixed[nextLoanId].time = now;
        loanInfoFixed[nextLoanId].rate = rate;
        loanInfoFixed[nextLoanId].minimumLTV = minimumLTV;
        loanInfoFixed[nextLoanId].maximumLTV = maximumLTV;
        ++nextLoanId;
    }

    /**
     * @dev See {ICalculator-payBackInFull}.
     */
    function payBackInFull(uint256 _loanId) external override {
        require(msg.sender == sodaMaster.bank(), "sender not bank");

        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            address who;  // The user that creats the loan.
            uint256 amount;  // How many SoETH tokens the user has lended.
            uint256 lockedAmount;  // How many WETH tokens the user has locked.
            uint256 time;  // When the loan is created or updated.
            uint256 rate;  // At what daily interest rate the user lended.
            uint256 minimumLTV;  // At what minimum loan-to-deposit ratio the user lended.
            uint256 maximumLTV;

            (who, amount, lockedAmount, time, rate, minimumLTV, maximumLTV) = oldCalculator.loanInfo(_loanId);

            loanInfoFixed[_loanId].who = who;
            // loanInfoFixed[_loanId].amount = amount;
            // loanInfoFixed[_loanId].lockedAmount = lockedAmount;
            // loanInfoFixed[_loanId].time = time;
            loanInfoFixed[_loanId].rate = rate;
            loanInfoFixed[_loanId].minimumLTV = minimumLTV;
            loanInfoFixed[_loanId].maximumLTV = maximumLTV;
            loanInfoFixed[_loanId].filledByOld = true;
        }

        loanInfoFixed[_loanId].amount = 0;
        loanInfoFixed[_loanId].lockedAmount = 0;

        loanInfoFixed[_loanId].time = now;
    }

    /**
     * @dev See {ICalculator-collectDebt}.
     */
    function collectDebt(uint256 _loanId) external override {
        require(msg.sender == sodaMaster.bank(), "sender not bank");

        if (_loanId < LOAN_ID_START && !loanInfoFixed[_loanId].filledByOld) {
            address who;  // The user that creats the loan.
            uint256 amount;  // How many SoETH tokens the user has lended.
            uint256 lockedAmount;  // How many WETH tokens the user has locked.
            uint256 time;  // When the loan is created or updated.
            uint256 rate;  // At what daily interest rate the user lended.
            uint256 minimumLTV;  // At what minimum loan-to-deposit ratio the user lended.
            uint256 maximumLTV;

            (who, amount, lockedAmount, time, rate, minimumLTV, maximumLTV) = oldCalculator.loanInfo(_loanId);

            loanInfoFixed[_loanId].who = who;
            loanInfoFixed[_loanId].amount = amount;
            loanInfoFixed[_loanId].lockedAmount = lockedAmount;
            loanInfoFixed[_loanId].time = time;
            loanInfoFixed[_loanId].rate = rate;
            loanInfoFixed[_loanId].minimumLTV = minimumLTV;
            loanInfoFixed[_loanId].maximumLTV = maximumLTV;
            loanInfoFixed[_loanId].filledByOld = true;
        }

        uint256 loanTotal = getLoanTotal(_loanId);
        uint256 maximumLoan = loanInfoFixed[_loanId].lockedAmount.mul(loanInfoFixed[_loanId].maximumLTV).div(LTV_BASE);

        // You can collect only if the user defaults.
        require(loanTotal >= maximumLoan, "collectDebt: >=");

        // Now the debt is clear. SodaPool, please do the rest.
        loanInfoFixed[_loanId].amount = 0;
        loanInfoFixed[_loanId].lockedAmount = 0;
        loanInfoFixed[_loanId].time = now;
    }
}
