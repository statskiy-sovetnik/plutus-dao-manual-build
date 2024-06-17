// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import { IArbDepositor, IPlutusChef } from './Interfaces.sol';

interface IStakingHelper {
  function convertAndStake(uint128 _amount) external;
}

contract PlsArbStakingHelper is Ownable, IStakingHelper {
  using SafeERC20 for IERC20;
  IERC20 public constant ARB = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
  IERC20 public immutable plsARB;
  IArbDepositor public immutable DEPOSITOR;
  IPlutusChef public immutable CHEF;

  constructor(address _depositor, address _plsArb, address _chef, address _gov) {
    DEPOSITOR = IArbDepositor(_depositor);
    plsARB = IERC20(_plsArb);
    CHEF = IPlutusChef(_chef);
    transferOwnership(_gov);
  }

  function convertAndStake(uint128 _amount) external {
    if (_amount < 1 ether) revert FAILED('min deposit: 1 ARB');
    if (tx.origin != msg.sender) revert FAILED(':(');

    ARB.safeTransferFrom(msg.sender, address(this), _amount);
    ARB.approve(address(DEPOSITOR), _amount);
    DEPOSITOR.depositFor(msg.sender, _amount);

    if (plsARB.balanceOf(address(this)) != _amount) revert FAILED(':(');

    plsARB.approve(address(CHEF), _amount);
    CHEF.depositFor(msg.sender, uint128(_amount));
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  error FAILED(string reason);
}