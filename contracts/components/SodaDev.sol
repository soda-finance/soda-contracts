// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../uniswapv2/interfaces/IUniswapV2Pair.sol";
import "../uniswapv2/interfaces/IUniswapV2Factory.sol";
import "../SodaMaster.sol";

// This contract is owned by the dev.
// When new SODAs are minted, 5% will be sent here.
// Anyone can purchase SODA with soETH with a 5% discount.
// dev can withdraw any token other than SODA from it.
contract SodaDev is Ownable {
    using SafeMath for uint256;

    uint256 constant K_MADE_SOETH = 0;

    SodaMaster public sodaMaster;

    constructor(SodaMaster _sodaMaster) public {
        sodaMaster = _sodaMaster;
    }

    // Anyone can buy Soda with 5% discount.
    function buySodaWithSoETH(uint256 _soETHAmount) public {
        address soETH = sodaMaster.sodaMadeByKey(K_MADE_SOETH);
        IERC20(soETH).transferFrom(msg.sender, address(this), _soETHAmount);
        uint256 sodaAmount = _soETHAmount.mul(getSodaToSoETHRate()) / 95;
        IERC20(sodaMaster.soda()).transfer(msg.sender, sodaAmount);
    }

    // Dev can withdraw any token other than SODA and ETH.
    // Don't send ETH to this contract!
    function withdrawToken(address _token, uint256 _tokenAmount) public onlyOwner {
        require(_token != sodaMaster.soda(), "anything other than SODA");

        IERC20(_token).transfer(msg.sender, _tokenAmount);
    }

    // How many sodas can be bought by 100 SoETH.
    function getSodaToSoETHRate() public view returns (uint256) {
        address soETH = sodaMaster.sodaMadeByKey(K_MADE_SOETH);

        (uint256 r0, uint256 r1) = getReserveRatio(sodaMaster.wETH(), soETH);
        (uint256 r2, uint256 r3) = getReserveRatio(sodaMaster.wETH(), sodaMaster.soda());
        return r3.mul(r0).mul(100).div(r2).div(r1);
    }

    function getReserveRatio(address token0, address token1) public view returns (uint256, uint256) {
        IUniswapV2Factory factory = IUniswapV2Factory(sodaMaster.uniswapV2Factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(token0, token1));
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        if (pair.token0() == token0) {
            return (reserve0, reserve1);
        } else {
            return (reserve1, reserve0);
        }
    }
}
