// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

abstract contract OwnableWithRetrieve is Ownable {
  /**
    Retrieve stuck funds. Will also send any native ETH in contract to owner()
   */
  function retrieve(IERC20 token) external onlyOwner {
    if ((address(this).balance) != 0) {
      owner().call{ value: address(this).balance }('');
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }
}