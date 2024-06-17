// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable2Step.sol';
import { IStaker, ITokenMinter } from './Interfaces.sol';
import { IWhitelist } from '../misc/Whitelist.sol';

contract ArbDepositor is Ownable2Step, Pausable {
  using SafeERC20 for IERC20;

  IERC20 public immutable arb; //0x912CE59144191C1204E64559FE8253a0e49E6548
  address public immutable minter;
  address public immutable staker;

  IWhitelist public whitelist;
  mapping(address => bool) handlers;

  constructor(address _arb, address _staker, address _minter) {
    arb = IERC20(_arb);
    staker = _staker;
    minter = _minter;
    _pause();
  }

  /**
   * Deposit asset for plsAsset
   */
  function deposit(uint256 _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function depositAll() external {
    deposit(arb.balanceOf(msg.sender));
  }

  function depositFor(address _user, uint256 _amount) external whenNotPaused {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _from, address _user, uint256 _amount) private {
    if (_amount < 1 ether) revert FAILED('min deposit: 1 ARB');

    arb.safeTransferFrom(_from, staker, _amount);
    IStaker(staker).stake(_amount);
    ITokenMinter(minter).mint(_from, _amount);

    emit Deposited(_user, _amount);
  }

  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false)
      revert UNAUTHORIZED();
  }

  /** OWNER FUNCTIONS */
  function setWhitelist(address _whitelist) external onlyOwner {
    emit WhitelistUpdated(_whitelist, address(whitelist));
    whitelist = IWhitelist(_whitelist);
  }

  function setHandler(address _handler, bool _isActive) external onlyOwner {
    handlers[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  /**
    Retrieve stuck funds
   */
  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  event WhitelistUpdated(address _new, address _old);
  event HandlerUpdated(address _address, bool _isActive);
  event Deposited(address indexed _user, uint256 _amount);

  error FAILED(string reason);
  error UNAUTHORIZED();
}