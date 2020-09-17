// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";
import "./tokens/SodaVault.sol";
import "./calculators/ICalculator.sol";
import "./components/SodaPool.sol";
import "./components/SodaBank.sol";
import "./strategies/CreateSoda.sol";

// Query data related to soda.
// This contract is owned by Timelock.
contract SodaDataBoard is Ownable {

    SodaMaster public sodaMaster;

    constructor(SodaMaster _sodaMaster) public {
        sodaMaster = _sodaMaster;
    }

    function getCalculatorStat(uint256 _poolId) public view returns(uint256, uint256, uint256) {
        ICalculator calculator;
        (,, calculator) = SodaBank(sodaMaster.bank()).poolMap(_poolId);
        uint256 rate = calculator.rate();
        uint256 minimumLTV = calculator.minimumLTV();
        uint256 maximumLTV = calculator.maximumLTV();
        return (rate, minimumLTV, maximumLTV);
    }

    function getPendingReward(uint256 _poolId, uint256 _index) public view returns(uint256) {
        SodaVault vault;
        (, vault,) = SodaPool(sodaMaster.pool()).poolMap(_poolId);
        return vault.getPendingReward(msg.sender, _index);
    }

    // get APY * 100
    function getAPY(uint256 _poolId, address _token, bool _isLPToken) public view returns(uint256) {
        (, SodaVault vault,) = SodaPool(sodaMaster.pool()).poolMap(_poolId);

        uint256 MK_STRATEGY_CREATE_SODA = 0;
        CreateSoda createSoda = CreateSoda(sodaMaster.strategyByKey(MK_STRATEGY_CREATE_SODA));
        (uint256 allocPoint,) = createSoda.poolMap(address(vault));
        uint256 totalAlloc = createSoda.totalAllocPoint();

        if (totalAlloc == 0) {
            return 0;
        }

        uint256 vaultSupply = vault.totalSupply();

        uint256 factor = 1;  // 1 SODA per block

        if (vaultSupply == 0) {
            // Assume $1 is put in.
            return getSodaPrice() * factor * 5760 * 100 * allocPoint / totalAlloc / 1e6;
        }

        // 2250000 is the estimated yearly block number of ethereum.
        // 1e18 comes from vaultSupply.
        if (_isLPToken) {
            uint256 lpPrice = getEthLpPrice(_token);
            if (lpPrice == 0) {
                return 0;
            }

            return getSodaPrice() * factor * 2250000 * 100 * allocPoint * 1e18 / totalAlloc / lpPrice / vaultSupply;
        } else {
            uint256 tokenPrice = getTokenPrice(_token);
            if (tokenPrice == 0) {
                return 0;
            }

            return getSodaPrice() * factor * 2250000 * 100 * allocPoint * 1e18 / totalAlloc / tokenPrice / vaultSupply;
        }
    }

    // return user loan record size.
    function getUserLoanLength(address _who) public view returns (uint256) {
        return SodaBank(sodaMaster.bank()).getLoanListLength(_who);
    }

    // return loan info (loanId,principal, interest, lockedAmount, time, rate, maximumLTV)
    function getUserLoan(address _who, uint256 _index) public view returns (uint256,uint256,uint256,uint256,uint256,uint256,uint256) {
        uint256 poolId;
        uint256 loanId;
        (poolId, loanId) = SodaBank(sodaMaster.bank()).loanList(_who, _index);

        ICalculator calculator;
        (,, calculator) = SodaBank(sodaMaster.bank()).poolMap(poolId);

        uint256 lockedAmount = calculator.getLoanLockedAmount(loanId);
        uint256 principal = calculator.getLoanPrincipal(loanId);
        uint256 interest = calculator.getLoanInterest(loanId);
        uint256 time = calculator.getLoanTime(loanId);
        uint256 rate = calculator.getLoanRate(loanId);
        uint256 maximumLTV = calculator.getLoanMaximumLTV(loanId);

        return (loanId, principal, interest, lockedAmount, time, rate, maximumLTV);
    }

    function getEthLpPrice(address _token) public view returns (uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(sodaMaster.uniswapV2Factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(_token, sodaMaster.wETH()));
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        if (pair.token0() == _token) {
            return reserve1 * getEthPrice() * 2 / pair.totalSupply();
        } else {
            return reserve0 * getEthPrice() * 2 / pair.totalSupply();
        }
    }

    // Return the 6 digit price of eth on uniswap.
    function getEthPrice() public view returns (uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(sodaMaster.uniswapV2Factory());
        IUniswapV2Pair ethUSDTPair = IUniswapV2Pair(factory.getPair(sodaMaster.wETH(), sodaMaster.usdt()));
        require(address(ethUSDTPair) != address(0), "ethUSDTPair need set by owner");
        (uint reserve0, uint reserve1,) = ethUSDTPair.getReserves();
        // USDT has 6 digits and WETH has 18 digits.
        // To get 6 digits after floating point, we need 1e18.
        if (ethUSDTPair.token0() == sodaMaster.wETH()) {
            return reserve1 * 1e18 / reserve0;
        } else {
            return reserve0 * 1e18 / reserve1;
        }
    }

    // Return the 6 digit price of soda on uniswap.
    function getSodaPrice() public view returns (uint256) {
        return getTokenPrice(sodaMaster.soda());
    }

    // Return the 6 digit price of any token on uniswap.
    function getTokenPrice(address _token) public view returns (uint256) {
        if (_token == sodaMaster.wETH()) {
            return getEthPrice();
        }

        IUniswapV2Factory factory = IUniswapV2Factory(sodaMaster.uniswapV2Factory());
        IUniswapV2Pair tokenETHPair = IUniswapV2Pair(factory.getPair(_token, sodaMaster.wETH()));
        require(address(tokenETHPair) != address(0), "tokenETHPair need set by owner");
        (uint reserve0, uint reserve1,) = tokenETHPair.getReserves();

        if (reserve0 == 0 || reserve1 == 0) {
            return 0;
        }

        // For 18 digits tokens, we will return 6 digits price.
        if (tokenETHPair.token0() == _token) {
            return getEthPrice() * reserve1 / reserve0;
        } else {
            return getEthPrice() * reserve0 / reserve1;
        }
    }
}
