// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IStaker, IERC20VotesUpgradeable } from './Interfaces.sol';

contract ArbStaker is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IStaker {
  IERC20VotesUpgradeable public constant ARB =
    IERC20VotesUpgradeable(0x912CE59144191C1204E64559FE8253a0e49E6548);
  address public depositor;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
  }

  function stake(uint _amount) external {
    if (msg.sender != depositor) revert UNAUTHORIZED();
    //noOp
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function setDelegate(address _delegatee) external onlyOwner {
    ARB.delegate(_delegatee);
  }

  function setDepositor(address _newDepositor) external onlyOwner {
    emit DepositorChanged(_newDepositor, depositor);
    depositor = _newDepositor;
  }

  event DepositorChanged(address indexed _new, address _old);

  error UNAUTHORIZED();
  error FAILED(string reason);
}