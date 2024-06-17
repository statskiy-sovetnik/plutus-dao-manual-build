// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable2Step.sol';
import { IRdntLpStaker, ITokenMinter } from './Interfaces.sol';
import { IWhitelist } from '../misc/Whitelist.sol';

contract RdntDepositor is Ownable2Step, Pausable {
  using SafeERC20 for IERC20;

  IERC20 public immutable dlp;
  address public immutable minter;
  address public immutable staker;

  IWhitelist public whitelist;
  address public zapper;

  constructor(address _dlp, address _staker, address _minter) {
    dlp = IERC20(_dlp);
    staker = _staker;
    minter = _minter;
    _pause();
  }

  /**
   * Deposit asset for plsAsset
   */
  function deposit(uint256 _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, _amount);
  }

  function depositAll() external {
    deposit(dlp.balanceOf(msg.sender));
  }

  function depositFor(address _user, uint256 _amount) external whenNotPaused {
    if (msg.sender != zapper) revert UNAUTHORIZED();
    _deposit(_user, _amount);
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _user, uint256 _amount) private {
    if (_amount == 0) revert ZERO_AMOUNT();

    dlp.safeTransferFrom(_user, staker, _amount);
    IRdntLpStaker(staker).stake(_amount);
    ITokenMinter(minter).mint(_user, _amount);

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

  function setZapper(address _zapper) external onlyOwner {
    emit ZapperUpdated(_zapper, address(zapper));
    zapper = _zapper;
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
  event ZapperUpdated(address _new, address _old);
  event Deposited(address indexed _user, uint256 _amount);

  error ZERO_AMOUNT();
  error UNAUTHORIZED();
}