// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../SodaMaster.sol";

// This contract is owned by Timelock.
contract SodaRevenue is Ownable {

    uint256 constant MK_STRATEGY_SHARE_REVENUE = 2;

    SodaMaster public sodaMaster;

    constructor(SodaMaster _sodaMaster) public {
        sodaMaster = _sodaMaster;
    }

    // Only shareRevenue can call this method. Currently _token is soETH.
    function distribute(address _token) external {
        address shareRevenue = sodaMaster.strategyByKey(MK_STRATEGY_SHARE_REVENUE);
        require(msg.sender == shareRevenue, "sender not share-revenue");

        address dev = sodaMaster.dev();

        uint256 amount = IERC20(_token).balanceOf(address(this));
        // 10% goes to dev.
        IERC20(_token).transfer(dev, amount / 10);
        // 90% goes to SODA_ETH_UNI_LP holders.
        IERC20(_token).transfer(shareRevenue, amount - amount / 10);
    }
}
