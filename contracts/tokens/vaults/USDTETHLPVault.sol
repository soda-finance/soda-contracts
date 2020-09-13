// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "../SodaVault.sol";

// Owned by Timelock
contract USDTETHLPVault is SodaVault {

    constructor (
        SodaMaster _sodaMaster,
        IStrategy _eatSushi,
        IStrategy _createSoda
    ) SodaVault(_sodaMaster, "Soda USDT-ETH-LP Vault", "vUSDT-ETH-LP") public  {
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = _eatSushi;
        strategies[1] = _createSoda;
        setStrategies(strategies);
    }
}
