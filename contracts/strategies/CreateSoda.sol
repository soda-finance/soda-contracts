// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../tokens/SodaToken.sol";
import "./IStrategy.sol";
import "../SodaMaster.sol";

// This contract has the power to change SODA allocation among
// different pools, but can't mint more than 330,000,000 SODA tokens.
// With ALL_BLOCKS_AMOUNT, BONUS_BLOCKS_AMOUNT, SODA_PER_BLOCK, and BONUS_MULTIPLIER,
// we have 10,0000 * 100 * 10 + 230,0000 * 100 = 330,000,000
// This contract is the only owner of SodaToken and is itself owned by Timelock.
contract CreateSoda is IStrategy, Ownable {
    using SafeMath for uint256;

    uint256 public constant ALL_BLOCKS_AMOUNT = 2400000;
    uint256 public constant BONUS_BLOCKS_AMOUNT = 100000;
    uint256 public constant SODA_PER_BLOCK = 100 * 1e18;
    uint256 public constant BONUS_MULTIPLIER = 10;

    uint256 constant PER_SHARE_SIZE = 1e12;

    // Info of each pool.
    struct PoolInfo {
        uint256 allocPoint;       // How many allocation points assigned to this pool. SODAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SODAs distribution occurs.
    }

    // Info of each pool.
    mapping (address => PoolInfo) public poolMap;  // By vault address.
    // pool length
    mapping (uint256 => address) public vaultMap;
    uint256 public poolLength;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The first block.
    uint256 public startBlock;

    // startBlock + ALL_BLOCKS_AMOUNT
    uint256 public endBlock;

    // Block number when bonus SODA period ends.
    // startBlock + BONUS_BLOCKS_AMOUNT
    uint256 public bonusEndBlock;

    // The SODA Pool.
    SodaMaster public sodaMaster;

    mapping(address => uint256) private valuePerShare;  // By vault.

    constructor(
        SodaMaster _sodaMaster
    ) public {
        sodaMaster = _sodaMaster;

        // Approve all.
        IERC20(sodaMaster.soda()).approve(sodaMaster.pool(), type(uint256).max);
    }

    // Admin calls this function.
    function setPoolInfo(
        uint256 _poolId,
        address _vault,
        IERC20 _token,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        if (_poolId >= poolLength) {
            poolLength = _poolId + 1;
        }

        vaultMap[_poolId] = _vault;

        if (poolMap[_vault].allocPoint == 0) {
            uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
            poolMap[_vault].lastRewardBlock = lastRewardBlock;
        }

        totalAllocPoint = totalAllocPoint.sub(poolMap[_vault].allocPoint).add(_allocPoint);
        poolMap[_vault].allocPoint = _allocPoint;

        _token.approve(sodaMaster.pool(), type(uint256).max);
    }

    // Admin calls this function.
    function approve(IERC20 _token) external override onlyOwner {
        _token.approve(sodaMaster.pool(), type(uint256).max);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to > endBlock) {
            _to = endBlock;
        }

        if (_from >= _to) {
            return 0;
        }

        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    function getValuePerShare(address _vault) external view override returns(uint256) {
        return valuePerShare[_vault];
    }

    function pendingValuePerShare(address _vault) external view override returns (uint256) {
        PoolInfo storage pool = poolMap[_vault];

        uint256 amountInVault = IERC20(_vault).totalSupply();
        if (block.number > pool.lastRewardBlock && amountInVault > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 sodaReward = multiplier.mul(SODA_PER_BLOCK).mul(pool.allocPoint).div(totalAllocPoint);
            sodaReward = sodaReward.sub(sodaReward.div(20));
            return sodaReward.mul(PER_SHARE_SIZE).div(amountInVault);
        } else {
            return 0;
        }
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        for (uint256 i = 0; i < poolLength; ++i) {
            _update(vaultMap[i]);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function _update(address _vault) public {
        PoolInfo storage pool = poolMap[_vault];

        if (pool.allocPoint <= 0) {
            return;
        }

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount == 0) {
            // Only after now >= pool.startTime in SodaPool, shareAmount can be larger than 0.
            return;
        }

        if (pool.lastRewardBlock == 0) {
            // This is the first time that we start counting blocks.
            pool.lastRewardBlock = block.number;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 allReward = multiplier.mul(SODA_PER_BLOCK).mul(pool.allocPoint).div(totalAllocPoint);
        SodaToken(sodaMaster.soda()).mint(sodaMaster.dev(), allReward.div(20));  // 5% goes to dev.
        uint256 farmerReward = allReward.sub(allReward.div(20));
        SodaToken(sodaMaster.soda()).mint(address(this), farmerReward);  // 95% goes to farmers.

        valuePerShare[_vault] = valuePerShare[_vault].add(farmerReward.mul(PER_SHARE_SIZE).div(shareAmount));
        pool.lastRewardBlock = block.number;
    }

    /**
     * @dev See {IStrategy-deposit}.
     */
    function deposit(address _vault, uint256 _amount) external override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        if (startBlock == 0) {
            startBlock = block.number;
            endBlock = startBlock + ALL_BLOCKS_AMOUNT;
            bonusEndBlock = startBlock + BONUS_BLOCKS_AMOUNT;
        }

        _update(_vault);
    }

    /**
     * @dev See {IStrategy-claim}.
     */
    function claim(address _vault) external override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        _update(_vault);
    }

    /**
     * @dev See {IStrategy-withdraw}.
     */
    function withdraw(address _vault, uint256 _amount) external override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        _update(_vault);
    }

    /**
     * @dev See {IStrategy-getTargetToken}.
     */
    function getTargetToken() external view override returns(address) {
        return sodaMaster.soda();
    }
}
