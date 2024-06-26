// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IWhitelist } from '../Whitelist.sol';
import { IFeeClaimer } from './interfaces.sol';

contract PlsSpaPlutusChef is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
  uint256 private constant MUL_CONSTANT = 1e14;
  IFeeClaimer public constant feeClaimer = IFeeClaimer(0x070344792CC8930bD8D91a3b2Ac65c79b92EF7A2);
  IERC20 public constant stakingToken = IERC20(0x0D111e482146fE9aC9cA3A65D92E65610BBC1Ba6);
  IERC20 public constant pls = IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F);
  IERC20 public constant spa = IERC20(0x5575552988A3A80504bBaeB1311674fCFd40aD4B);

  // Info of each user.
  struct UserInfo {
    uint96 amount; // Staking tokens the user has provided
    int128 plsRewardDebt;
    int128 spaRewardDebt;
  }

  IWhitelist public whitelist;
  address public operator;

  uint128 public plsPerSecond;
  uint128 public accSpaPerShare;
  uint128 public accPlsPerShare;
  uint96 private shares; // total staked
  uint32 public lastRewardSecond;

  mapping(address => UserInfo) public userInfo;

  bool private isAccSpaPerShareReset;
  mapping(address => bool) private isUserRewardDebtReset;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Pausable_init();
    __Ownable_init();
    __UUPSUpgradeable_init();
    lastRewardSecond = 1665187200;
  }

  function deposit(uint96 _amount) external {
    _isEligibleSender();
    _deposit(msg.sender, _amount);
  }

  function withdraw(uint96 _amount) external {
    _isEligibleSender();
    _withdraw(msg.sender, _amount);
  }

  function harvest() external {
    _isEligibleSender();
    _harvest(msg.sender);
  }

  /**
   * Withdraw without caring about rewards. EMERGENCY ONLY.
   */
  function emergencyWithdraw() external {
    _isEligibleSender();
    UserInfo storage user = userInfo[msg.sender];

    uint96 _amount = user.amount;

    user.amount = 0;
    user.plsRewardDebt = 0;
    user.spaRewardDebt = 0;

    if (shares >= _amount) {
      shares -= _amount;
    } else {
      shares = 0;
    }

    stakingToken.transfer(msg.sender, _amount);
    emit EmergencyWithdraw(msg.sender, _amount);
  }

  /**
    Keep reward variables up to date. Ran before every mutative function.
   */
  function updateShares() public whenNotPaused {
    // if block.timestamp <= lastRewardSecond, already updated.
    if (block.timestamp <= lastRewardSecond) {
      return;
    }

    if (isUserRewardDebtReset[msg.sender] == false) {
      userInfo[msg.sender].spaRewardDebt = 0;
      isUserRewardDebtReset[msg.sender] = true;
    }

    // if pool has no supply
    if (shares == 0) {
      lastRewardSecond = uint32(block.timestamp);
      return;
    }

    unchecked {
      accPlsPerShare += rewardPerShare(plsPerSecond);

      (uint256 pendingSpaRewardsLessFee, ) = feeClaimer.pendingRewards();
      if (pendingSpaRewardsLessFee > 0) {
        accSpaPerShare += uint128((pendingSpaRewardsLessFee * MUL_CONSTANT) / shares);
      }
    }

    feeClaimer.harvest();
    lastRewardSecond = uint32(block.timestamp);
  }

  /** OPERATOR */
  function depositFor(address _user, uint88 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _deposit(_user, _amount);
  }

  function withdrawFor(address _user, uint88 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _withdraw(_user, _amount);
  }

  function harvestFor(address _user) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _harvest(_user);
  }

  /** VIEWS */

  /**
    Calculates the reward per share since `lastRewardSecond` was updated
  */
  function rewardPerShare(uint256 _rewardRatePerSecond) public view returns (uint128) {
    // duration = block.timestamp - lastRewardSecond;
    // tokenReward = duration * _rewardRatePerSecond;
    // tokenRewardPerShare = (tokenReward * MUL_CONSTANT) / shares;

    unchecked {
      return uint128(((block.timestamp - lastRewardSecond) * _rewardRatePerSecond * MUL_CONSTANT) / shares);
    }
  }

  /**
    View function to see pending rewards on frontend
   */
  function pendingRewards(address _user) external view returns (uint256 _pendingPls, uint256 _pendingSpa) {
    uint256 _plsPS = accPlsPerShare;
    uint256 _spaPS = accSpaPerShare;

    if (block.timestamp > lastRewardSecond && shares != 0) {
      (uint256 pendingSpaRewardsLessFee, ) = feeClaimer.pendingRewards();
      if (pendingSpaRewardsLessFee > 0) {
        _spaPS += uint128((pendingSpaRewardsLessFee * MUL_CONSTANT) / shares);
      }

      _plsPS += rewardPerShare(plsPerSecond);
    }

    UserInfo memory user = userInfo[_user];

    int128 userSpaRewardDebt = user.spaRewardDebt;
    if (isUserRewardDebtReset[_user] == false) {
      userSpaRewardDebt = 0;
    }

    _pendingPls = _calculatePending(user.plsRewardDebt, _plsPS, user.amount);
    _pendingSpa = _calculatePending(userSpaRewardDebt, _spaPS, user.amount);
  }

  /** PRIVATE */
  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  function _calculatePending(
    int128 _rewardDebt,
    uint256 _accPerShare, // Stay 256;
    uint96 _amount
  ) private pure returns (uint128) {
    if (_rewardDebt < 0) {
      return uint128(_calculateRewardDebt(_accPerShare, _amount)) + uint128(-_rewardDebt);
    } else {
      return uint128(_calculateRewardDebt(_accPerShare, _amount)) - uint128(_rewardDebt);
    }
  }

  function _calculateRewardDebt(uint256 _accTokenPerShare, uint96 _amount) private pure returns (uint256) {
    unchecked {
      return (_amount * _accTokenPerShare) / MUL_CONSTANT;
    }
  }

  function _safeTokenTransfer(
    IERC20 _token,
    address _to,
    uint256 _amount
  ) private {
    uint256 bal = _token.balanceOf(address(this));

    if (_amount > bal) {
      _token.transfer(_to, bal);
    } else {
      _token.transfer(_to, _amount);
    }
  }

  function _deposit(address _user, uint96 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (_amount == 0) revert DEPOSIT_ERROR();
    updateShares();

    uint256 _prev = stakingToken.balanceOf(address(this));

    unchecked {
      user.amount += _amount;
      shares += _amount;
    }

    user.plsRewardDebt = user.plsRewardDebt + int128(uint128(_calculateRewardDebt(accPlsPerShare, _amount)));
    user.spaRewardDebt = user.spaRewardDebt + int128(uint128(_calculateRewardDebt(accSpaPerShare, _amount)));

    stakingToken.transferFrom(_user, address(this), _amount);

    unchecked {
      if (_prev + _amount != stakingToken.balanceOf(address(this))) revert DEPOSIT_ERROR();
    }

    emit Deposit(_user, _amount);
  }

  function _withdraw(address _user, uint96 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (user.amount < _amount || _amount == 0) revert WITHDRAW_ERROR();
    updateShares();

    unchecked {
      user.amount -= _amount;
      shares -= _amount;
    }

    user.plsRewardDebt = user.plsRewardDebt - int128(uint128(_calculateRewardDebt(accPlsPerShare, _amount)));
    user.spaRewardDebt = user.spaRewardDebt - int128(uint128(_calculateRewardDebt(accSpaPerShare, _amount)));

    stakingToken.transfer(_user, _amount);
    emit Withdraw(_user, _amount);
  }

  function _harvest(address _user) private {
    updateShares();
    UserInfo storage user = userInfo[_user];

    uint256 plsPending = _calculatePending(user.plsRewardDebt, accPlsPerShare, user.amount);
    user.plsRewardDebt = int128(uint128(_calculateRewardDebt(accPlsPerShare, user.amount)));
    _safeTokenTransfer(pls, _user, plsPending);
    emit Harvest(_user, address(pls), plsPending);

    uint256 spaPending = _calculatePending(user.spaRewardDebt, accSpaPerShare, user.amount);
    if (spaPending > 0) {
      user.spaRewardDebt = int128(uint128(_calculateRewardDebt(accSpaPerShare, user.amount)));
      _safeTokenTransfer(spa, _user, spaPending);
      emit Harvest(_user, address(spa), spaPending);
    }
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  function setWhitelist(address _whitelist) external onlyOwner {
    whitelist = IWhitelist(_whitelist);
  }

  function resetAccSpaPerShare() external onlyOwner {
    if (isAccSpaPerShareReset == false) {
      accSpaPerShare = 0;
      isAccSpaPerShareReset = true;
    }
  }

  function setOperator(address _operator) external onlyOwner {
    operator = _operator;
  }

  function setStartTime(uint32 _startTime) external onlyOwner {
    lastRewardSecond = _startTime;
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  function setEmission(uint128 _plsPerSecond) external {
    if (msg.sender == operator || msg.sender == owner()) {
      plsPerSecond = _plsPerSecond;
    } else {
      revert UNAUTHORIZED();
    }
  }

  error DEPOSIT_ERROR();
  error WITHDRAW_ERROR();
  error UNAUTHORIZED();

  event Deposit(address indexed _user, uint256 _amount);
  event Withdraw(address indexed _user, uint256 _amount);
  event Harvest(address indexed _user, address indexed _token, uint256 _amount);
  event EmergencyWithdraw(address indexed _user, uint256 _amount);
}