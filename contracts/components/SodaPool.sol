// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/SodaToken.sol";
import "../tokens/SodaVault.sol";
import "../strategies/IStrategy.sol";


// This contract is owned by Timelock.
contract SodaPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each pool.
    struct PoolInfo {
        IERC20 token;           // Address of token contract.
        SodaVault vault;           // Address of vault contract.
        uint256 startTime;
    }

    // Info of each pool.
    mapping (uint256 => PoolInfo) public poolMap;  // By poolId

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount);
    event Claim(address indexed user, uint256 indexed poolId);

    constructor() public {
    }

    function setPoolInfo(uint256 _poolId, IERC20 _token, SodaVault _vault, uint256 _startTime) public onlyOwner {
        poolMap[_poolId].token = _token;
        poolMap[_poolId].vault = _vault;
        poolMap[_poolId].startTime = _startTime;
    }

    function _handleDeposit(SodaVault _vault, IERC20 _token, uint256 _amount) internal {
        uint256 count = _vault.getStrategyCount();
        require(count == 1 || count == 2, "_handleDeposit: count");

        // NOTE: strategy0 is always the main strategy.
        address strategy0 = address(_vault.strategies(0));
        _token.safeTransferFrom(address(msg.sender), strategy0, _amount);
    }

    function _handleWithdraw(SodaVault _vault, IERC20 _token, uint256 _amount) internal {
        uint256 count = _vault.getStrategyCount();
        require(count == 1 || count == 2, "_handleWithdraw: count");

        address strategy0 = address(_vault.strategies(0));
        _token.safeTransferFrom(strategy0, address(msg.sender), _amount);
    }

    function _handleRewards(SodaVault _vault) internal {
        uint256 count = _vault.getStrategyCount();

        for (uint256 i = 0; i < count; ++i) {
            uint256 rewardPending = _vault.rewards(msg.sender, i);
            if (rewardPending > 0) {
                IERC20(_vault.strategies(i).getTargetToken()).safeTransferFrom(
                    address(_vault.strategies(i)), msg.sender, rewardPending);
            }
        }

        _vault.clearRewardByPool(msg.sender);
    }

    // Deposit tokens to SodaPool for SODA allocation.
    // If we have a strategy, then tokens will be moved there.
    function deposit(uint256 _poolId, uint256 _amount) public {
        PoolInfo storage pool = poolMap[_poolId];
        require(now >= pool.startTime, "deposit: after startTime");

        _handleDeposit(pool.vault, pool.token, _amount);
        pool.vault.mintByPool(msg.sender, _amount);

        emit Deposit(msg.sender, _poolId, _amount);
    }

    // Claim SODA (and potentially other tokens depends on strategy).
    function claim(uint256 _poolId) public {
        PoolInfo storage pool = poolMap[_poolId];
        require(now >= pool.startTime, "claim: after startTime");

        pool.vault.mintByPool(msg.sender, 0);
        _handleRewards(pool.vault);

        emit Claim(msg.sender, _poolId);
    }

    // Withdraw tokens from SodaPool (from a strategy first if there is one).
    function withdraw(uint256 _poolId, uint256 _amount) public {
        PoolInfo storage pool = poolMap[_poolId];
        require(now >= pool.startTime, "withdraw: after startTime");

        pool.vault.burnByPool(msg.sender, _amount);

        _handleWithdraw(pool.vault, pool.token, _amount);
        _handleRewards(pool.vault);

        emit Withdraw(msg.sender, _poolId, _amount);
    }
}
