// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "../SodaVault.sol";

// Don't need to be owned.
contract SODAETHLPVault is SodaVault {

    constructor (
        SodaMaster _sodaMaster,
        IStrategy _createSoda,
        IStrategy _shareRevenue
    ) SodaVault(_sodaMaster, "Soda SODA-ETH-LP Vault", "vSODA-ETH-LP") public  {
        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = _createSoda;
        strategies[1] = _shareRevenue;
        setStrategies(strategies);
    }
}
