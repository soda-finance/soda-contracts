// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../tokens/SodaToken.sol";
import "./IStrategy.sol";
import "../SodaMaster.sol";

// This contract has the power to change SODA allocation among
// different pools, but can't mint more than 100,000 SODA tokens.
// With ALL_BLOCKS_AMOUNT and SODA_PER_BLOCK,
// we have 100,000 * 1 = 100,000
//
// For the remaining 900,000 SODA, we will need to deploy a new contract called
// CreateMoreSoda after the community can make a decision by voting.
//
// Currently this contract is the only owner of SodaToken and is itself owned by
// Timelock, and it has a function transferToCreateMoreSoda to transfer the
// ownership to CreateMoreSoda once all the 100,000 tokens are out.
contract CreateSoda is IStrategy, Ownable {
    using SafeMath for uint256;

    uint256 public constant ALL_BLOCKS_AMOUNT = 100000;
    uint256 public constant SODA_PER_BLOCK = 1 * 1e18;

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

        return _to.sub(_from);
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

        if (pool.lastRewardBlock == 0) {
                // This is the first time that we start counting blocks.
            pool.lastRewardBlock = block.number;
        }

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount == 0) {
            // Only after now >= pool.startTime in SodaPool, shareAmount can be larger than 0.
            return;
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

    // This only happens after all the 100,000 tokens are minted, and should
    // be after the community can vote (I promise by then Timelock will
    // be administrated by GovernorAlpha).
    //
    // Community (of the future), please make sure _createMoreSoda contract is
    // safe enough to pull the trigger.
    function transferToCreateMoreSoda(address _createMoreSoda) external onlyOwner {
        require(block.number > endBlock);
        SodaToken(sodaMaster.soda()).transferOwnership(_createMoreSoda);
    }
}
