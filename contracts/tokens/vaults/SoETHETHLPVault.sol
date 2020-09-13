// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "../SodaVault.sol";

// Don't need to be owned.
contract SoETHETHLPVault is SodaVault {

    constructor (
        SodaMaster _sodaMaster,
        IStrategy _createSoda
    ) SodaVault(_sodaMaster, "Soda SoETH-ETH-LP Vault", "vSoETH-ETH-LP") public  {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = _createSoda;
        setStrategies(strategies);
    }
}
