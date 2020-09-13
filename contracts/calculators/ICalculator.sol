// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

// `TOKEN` can be any ERC20 token. The first one is WETH.
abstract contract ICalculator {

    function rate() external view virtual returns(uint256);
    function minimumLTV() external view virtual returns(uint256);
    function maximumLTV() external view virtual returns(uint256);

    // Get next loan Id.
    function getNextLoanId() external view virtual returns(uint256);

    // Get loan creator address.
    function getLoanCreator(uint256 _loanId) external view virtual returns (address);

    // Get the locked `TOKEN` amount by the loan.
    function getLoanLockedAmount(uint256 _loanId) external view virtual returns (uint256);

    // Get the time by the loan.
    function getLoanTime(uint256 _loanId) external view virtual returns (uint256);

    // Get the rate by the loan.
    function getLoanRate(uint256 _loanId) external view virtual returns (uint256);

    // Get the minimumLTV by the loan.
    function getLoanMinimumLTV(uint256 _loanId) external view virtual returns (uint256);

    // Get the maximumLTV by the loan.
    function getLoanMaximumLTV(uint256 _loanId) external view virtual returns (uint256);

    // Get the SoMade amount of the loan principal.
    function getLoanPrincipal(uint256 _loanId) external view virtual returns (uint256);

    // Get the SoMade amount of the loan interest.
    function getLoanInterest(uint256 _loanId) external view virtual returns (uint256);

    // Get the SoMade amount that the user needs to pay back in full.
    function getLoanTotal(uint256 _loanId) external view virtual returns (uint256);

    // Get the extra fee for collection in SoMade.
    function getLoanExtra(uint256 _loanId) external view virtual returns (uint256);

    // Lend SoMade to create a new loan.
    //
    // Only SodaPool can call this contract, and SodaPool should make sure the
    // user has enough `TOKEN` deposited.
    function borrow(address _who, uint256 _amount) external virtual;

    // Pay back to a loan fully.
    //
    // Only SodaPool can call this contract.
    function payBackInFull(uint256 _loanId) external virtual;

    // Collect debt if someone defaults.
    //
    // Only SodaPool can call this contract, and SodaPool should send `TOKEN` to
    // the debt collector.
    function collectDebt(uint256 _loanId) external virtual;
}
