// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../SodaMade.sol";

// SodaEthereum is the 1st SodaMade, and should be owned by bank.
contract SodaEthereum is SodaMade("SodaEthereum", "SoETH") {
}
