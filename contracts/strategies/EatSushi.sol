// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";
import "../SodaMaster.sol";

interface IMasterChef {
    // Deposit LP tokens to MasterChef for SUSHI allocation.
    function deposit(uint256 _pid, uint256 _amount) external;
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external;

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
}

// This contract is owned by Timelock.
// What it does is simple: deposit USDT-ETH UNI-V2 LP to sushiswap, and wait for SodaPool's command.
contract EatSushi is IStrategy, Ownable {
    using SafeMath for uint256;

    uint256 constant PER_SHARE_SIZE = 1e12;

    IMasterChef public masterChef;

    SodaMaster public sodaMaster;
    IERC20 public sushiToken;

    struct PoolInfo {
        IERC20 lpToken;
        uint256 poolId;  // poolId in sushi pool.
    }

    mapping(address => PoolInfo) public poolMap;  // By vault.
    mapping(address => uint256) private valuePerShare;  // By vault.

    // usdtETHSLPToken = "0x06da0fd433C1A5d7a4faa01111c044910A184553"
    // sushiToken = "0x6b3595068778dd592e39a122f4f5a5cf09c90fe2"
    // masterChef = "0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd"
    // usdtETHLPId = 0
    constructor(SodaMaster _sodaMaster,
                IERC20 _sushiToken,
                IMasterChef _masterChef) public {
        sodaMaster = _sodaMaster;
        sushiToken = _sushiToken;
        masterChef = _masterChef;
        // Approve all.
        sushiToken.approve(sodaMaster.pool(), type(uint256).max);
    }

    function approve(IERC20 _token) external override onlyOwner {
        _token.approve(sodaMaster.pool(), type(uint256).max);
        _token.approve(address(masterChef), type(uint256).max);
    }

    function setPoolInfo(
        address _vault,
        IERC20 _lpToken,
        uint256 _sushiPoolId
    ) external onlyOwner {
        poolMap[_vault].lpToken = _lpToken;
        poolMap[_vault].poolId = _sushiPoolId;
        _lpToken.approve(sodaMaster.pool(), type(uint256).max);
        _lpToken.approve(address(masterChef), type(uint256).max);
    }

    function getValuePerShare(address _vault) external view override returns(uint256) {
        return valuePerShare[_vault];
    }

    function pendingValuePerShare(address _vault) external view override returns (uint256) {
        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount == 0) {
            return 0;
        }

        uint256 amount = masterChef.pendingSushi(poolMap[_vault].poolId, address(this));
        return amount.mul(PER_SHARE_SIZE).div(shareAmount);
    }

    function _update(address _vault, uint256 _tokenAmountDelta) internal {
        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount > 0) {
            valuePerShare[_vault] = valuePerShare[_vault].add(
                _tokenAmountDelta.mul(PER_SHARE_SIZE).div(shareAmount));
        }
    }

    /**
     * @dev See {IStrategy-deposit}.
     */
    function deposit(address _vault, uint256 _amount) public override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        uint256 tokenAmountBefore = sushiToken.balanceOf(address(this));
        masterChef.deposit(poolMap[_vault].poolId, _amount);
        uint256 tokenAmountAfter = sushiToken.balanceOf(address(this));

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore));
    }

    /**
     * @dev See {IStrategy-claim}.
     */
    function claim(address _vault) external override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        // Sushi is strage that it uses deposit to claim.
        deposit(_vault, 0);
    }

    /**
     * @dev See {IStrategy-withdraw}.
     */
    function withdraw(address _vault, uint256 _amount) external override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        uint256 tokenAmountBefore = sushiToken.balanceOf(address(this));
        masterChef.withdraw(poolMap[_vault].poolId, _amount);
        uint256 tokenAmountAfter = sushiToken.balanceOf(address(this));

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore));
    }

    /**
     * @dev See {IStrategy-getTargetToken}.
     */
    function getTargetToken() external view override returns(address) {
        return address(sushiToken);
    }
}
