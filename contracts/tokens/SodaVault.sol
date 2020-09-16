// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../strategies/IStrategy.sol";
import "../SodaMaster.sol";

// SodaVault is owned by Timelock
contract SodaVault is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 constant PER_SHARE_SIZE = 1e12;

    mapping (address => uint256) public lockedAmount;
    mapping (address => mapping(uint256 => uint256)) public rewards;
    mapping (address => mapping(uint256 => uint256)) public debts;

    IStrategy[] public strategies;

    SodaMaster public sodaMaster;

    constructor (SodaMaster _sodaMaster, string memory _name, string memory _symbol) ERC20(_name, _symbol) public  {
        sodaMaster = _sodaMaster;
    }

    function setStrategies(IStrategy[] memory _strategies) public onlyOwner {
        delete strategies;
        for (uint256 i = 0; i < _strategies.length; ++i) {
            strategies.push(_strategies[i]);
        }
    }

    function getStrategyCount() view public returns(uint count) {
        return strategies.length;
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by SodaPool.
    function mintByPool(address _to, uint256 _amount) public {
        require(_msgSender() == sodaMaster.pool(), "not pool");

        _deposit(_amount);
        _updateReward(_to);
        if (_amount > 0) {
            _mint(_to, _amount);
        }
        _updateDebt(_to);
    }

    // Must only be called by SodaPool.
    function burnByPool(address _account, uint256 _amount) public {
        require(_msgSender() == sodaMaster.pool(), "not pool");

        uint256 balance = balanceOf(_account);
        require(lockedAmount[_account] + _amount <= balance, "Vault: burn too much");

        _withdraw(_amount);
        _updateReward(_account);
        _burn(_account, _amount);
        _updateDebt(_account);
    }

    // Must only be called by SodaBank.
    function transferByBank(address _from, address _to, uint256 _amount) public {
        require(_msgSender() == sodaMaster.bank(), "not bank");

        uint256 balance = balanceOf(_from);
        require(lockedAmount[_from] + _amount <= balance);

        _claim();
        _updateReward(_from);
        _updateReward(_to);
        _transfer(_from, _to, _amount);
        _updateDebt(_to);
        _updateDebt(_from);
    }

    // Any user can transfer to another user.
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        uint256 balance = balanceOf(_msgSender());
        require(lockedAmount[_msgSender()] + _amount <= balance, "transfer: <= balance");

        _updateReward(_msgSender());
        _updateReward(_to);
        _transfer(_msgSender(), _to, _amount);
        _updateDebt(_to);
        _updateDebt(_msgSender());

        return true;
    }

    // Must only be called by SodaBank.
    function lockByBank(address _account, uint256 _amount) public {
        require(_msgSender() == sodaMaster.bank(), "not bank");

        uint256 balance = balanceOf(_account);
        require(lockedAmount[_account] + _amount <= balance, "Vault: lock too much");
        lockedAmount[_account] += _amount;
    }

    // Must only be called by SodaBank.
    function unlockByBank(address _account, uint256 _amount) public {
        require(_msgSender() == sodaMaster.bank(), "not bank");

        require(_amount <= lockedAmount[_account], "Vault: unlock too much");
        lockedAmount[_account] -= _amount;
    }

    // Must only be called by SodaPool.
    function clearRewardByPool(address _who) public {
        require(_msgSender() == sodaMaster.pool(), "not pool");

        for (uint256 i = 0; i < strategies.length; ++i) {
            rewards[_who][i] = 0;
        }
    }

    function getPendingReward(address _who, uint256 _index) public view returns (uint256) {
        uint256 total = totalSupply();
        if (total == 0 || _index >= strategies.length) {
            return 0;
        }

        uint256 value = strategies[_index].getValuePerShare(address(this));
        uint256 pending = strategies[_index].pendingValuePerShare(address(this));
        uint256 balance = balanceOf(_who);

        return balance.mul(value.add(pending)).div(PER_SHARE_SIZE).sub(debts[_who][_index]);
    }

    function _deposit(uint256 _amount) internal {
        for (uint256 i = 0; i < strategies.length; ++i) {
            strategies[i].deposit(address(this), _amount);
        }
    }

    function _withdraw(uint256 _amount) internal {
        for (uint256 i = 0; i < strategies.length; ++i) {
            strategies[i].withdraw(address(this), _amount);
        }
    }

    function _claim() internal {
        for (uint256 i = 0; i < strategies.length; ++i) {
            strategies[i].claim(address(this));
        }
    }

    function _updateReward(address _who) internal {
        uint256 balance = balanceOf(_who);
        if (balance > 0) {
            for (uint256 i = 0; i < strategies.length; ++i) {
                uint256 value = strategies[i].getValuePerShare(address(this));
                rewards[_who][i] = rewards[_who][i].add(balance.mul(
                    value).div(PER_SHARE_SIZE).sub(debts[_who][i]));
            }
        }
    }

    function _updateDebt(address _who) internal {
        uint256 balance = balanceOf(_who);
        for (uint256 i = 0; i < strategies.length; ++i) {
            uint256 value = strategies[i].getValuePerShare(address(this));
            debts[_who][i] = balance.mul(value).div(PER_SHARE_SIZE);
        }
    }
}
