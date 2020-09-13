// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// All SodaMade tokens should be owned by SodaBank.
contract SodaMade is ERC20, Ownable {

    constructor (string memory _name, string memory _symbol) ERC20(_name, _symbol) public  {
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (SodaBank).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    /// @notice Burns `_amount` token in `account`. Must only be called by the owner (SodaBank).
    function burnFrom(address account, uint256 amount) public onlyOwner {
        uint256 decreasedAllowance = allowance(account, _msgSender()).sub(amount, "ERC20: burn amount exceeds allowance");

        _approve(account, _msgSender(), decreasedAllowance);
        _burn(account, amount);
    }
}
