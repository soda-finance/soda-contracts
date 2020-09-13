// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../components/SodaRevenue.sol";
import "./IStrategy.sol";

// ShareRevenue calls SodaRevenue to get SoETH and share it to SODA-ETH-UNI-V2-LP stakers.
// This contract is owned by Timelock.
contract ShareRevenue is IStrategy, Ownable {
    using SafeMath for uint256;

    uint256 constant K_MADE_SOETH = 0;

    uint256 constant PER_SHARE_SIZE = 1e12;

    SodaMaster public sodaMaster;

    IERC20 public lpToken;

    mapping(address => uint256) private valuePerShare;  // By vault.

    constructor(SodaMaster _sodaMaster, IERC20 _lpToken) public {
        sodaMaster = _sodaMaster;

        _lpToken.approve(sodaMaster.pool(), type(uint256).max);
        IERC20(sodaMaster.sodaMadeByKey(K_MADE_SOETH)).approve(sodaMaster.pool(), type(uint256).max);
    }

    function approve(IERC20 _token) external override onlyOwner {
        _token.approve(sodaMaster.pool(), type(uint256).max);
    }

    function getValuePerShare(address _vault) external view override returns(uint256) {
        return valuePerShare[_vault];
    }

    function pendingValuePerShare(address _vault) external view override returns (uint256) {
        return 0;
    }

    function _update(address _vault, uint256 _tokenAmountDelta) internal {
        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount > 0) {
            valuePerShare[address(_vault)] = valuePerShare[address(_vault)].add(
                _tokenAmountDelta.mul(PER_SHARE_SIZE).div(shareAmount));
        }
    }

    /**
     * @dev See {IStrategy-deposit}.
     */
    function deposit(address _vault, uint256 _amount) public override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        claim(_vault);
    }

    /**
     * @dev See {IStrategy-claim}.
     */
    function claim(address _vault) public override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        address soETH = sodaMaster.sodaMadeByKey(K_MADE_SOETH);

        uint256 tokenAmountBefore = IERC20(soETH).balanceOf(address(this));
        SodaRevenue(sodaMaster.revenue()).distribute(soETH);
        uint256 tokenAmountAfter = IERC20(soETH).balanceOf(address(this));

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore));
    }

    /**
     * @dev See {IStrategy-withdraw}.
     */
    function withdraw(address _vault, uint256 _amount) public override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        claim(_vault);
    }

    /**
     * @dev See {IStrategy-getTargetToken}.
     */
    function getTargetToken() external view override returns(address) {
        return sodaMaster.sodaMadeByKey(K_MADE_SOETH);
    }
}
