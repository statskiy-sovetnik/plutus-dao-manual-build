// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './interfaces/IEpochStaking.sol';

contract EpochStakingController is Ownable {
  IEpochStaking[] public contracts;

  function addContract(address _contract) external onlyOwner {
    contracts.push(IEpochStaking(_contract));
  }

  function initAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].init();
    }
  }

  function setWhitelist(address _wl) external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].setWhitelist(_wl);
    }
  }

  function advanceEpochAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].advanceEpoch();
    }
  }

  function pauseAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].pause();
    }
  }

  function unpauseAll() external onlyOwner {
    for (uint256 i = 0; i < contracts.length; i++) {
      contracts[i].unpause();
    }
  }
}