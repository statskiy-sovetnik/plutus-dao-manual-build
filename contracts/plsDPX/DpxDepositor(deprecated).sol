// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IStaker.sol';
import '../interfaces/ITokenMinter.sol';
import { IWhitelist } from '../Whitelist.sol';

contract DpxDepositor is Ownable, Pausable {
  using SafeERC20 for IERC20;

  // DPX: 0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55
  IERC20 public immutable stakingToken;
  address public immutable minter; // plsDPX
  address public immutable staker;

  IWhitelist public whitelist;

  constructor(
    address _stakingToken,
    address _staker,
    address _minter
  ) {
    stakingToken = IERC20(_stakingToken);
    staker = _staker;
    minter = _minter;
    _pause();
  }

  /**
    Deposit asset for plsAsset
   */
  function deposit(uint256 _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, _amount);
  }

  function depositAll() external {
    deposit(stakingToken.balanceOf(msg.sender));
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _user, uint256 _amount) private {
    if (_amount == 0) revert ZERO_AMOUNT();

    stakingToken.safeTransferFrom(_user, staker, _amount);
    IStaker(staker).stake(_amount);
    ITokenMinter(minter).mint(_user, _amount);
  }

  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  /** OWNER FUNCTIONS */
  function setWhitelist(address _whitelist) external onlyOwner {
    emit WhitelistUpdated(_whitelist, address(whitelist));
    whitelist = IWhitelist(_whitelist);
  }

  /**
    Retrieve stuck funds or new reward tokens
   */
  function retrieve(IERC20 token) external onlyOwner {
    if ((address(this).balance) != 0) {
      payable(owner()).transfer(address(this).balance);
    }

    token.transfer(owner(), token.balanceOf(address(this)));
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  function depositFor(address _user, uint256 _amount) external onlyOwner {
    _deposit(_user, _amount);
  }

  function withdraw(address _user, uint256 _amount) external onlyOwner {
    ITokenMinter(minter).burn(_user, _amount);
    IStaker(staker).withdraw(_amount, _user);
  }

  event WhitelistUpdated(address _new, address _old);

  error ZERO_AMOUNT();
  error UNAUTHORIZED();
}