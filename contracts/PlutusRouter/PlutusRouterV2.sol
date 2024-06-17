// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';

import { IRewardTracker, IErrors, IBaseMintableToken, IBaseDistributor, IPlutusRouterCallback } from './Interfaces.sol';
import { ILockedToken } from './LockedToken.sol';
import { IBonusTracker } from './BonusTracker.sol';
import { ICheckpointer } from './Checkpointer.sol';

interface IPlutusRouterV2 {
  event Stake(address indexed _account, address indexed _token, uint _amount);

  event Unstake(address indexed _account, address indexed _token, uint _amount);

  struct TrackerSet {
    address staked;
    address bonus;
    address locked;
    address checkpointer;
  }

  function claimAndStakeMpPls() external;

  function stakeEsPls(uint _amount) external;

  function stakeAndLockPlsWeth(uint _amount) external;

  function stakeAndLockPls(uint _amount) external;

  function unstakeEsPls(uint _amount) external;

  function unlockAndUnstakePls() external;

  function unlockAndUnstakePlsWeth() external;
}

contract PlutusRouterV2 is
  IPlutusRouterV2,
  IErrors,
  Initializable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  address public constant pls = 0x51318B7D00db7ACc4026C88c3952B66278B6A67F;
  address public mpPls;
  address public esPls;
  address public constant plsWeth = 0xbFD465E270F8D6bA62b5000cD27D155FB5aE70f0;

  address public stakedPlsTracker;
  address public bonusPlsTracker;
  ILockedToken public lockedPls;
  address public plsCheckpointer;

  address public stakedPlsWethTracker;
  address public bonusPlsWethTracker;
  ILockedToken public lockedPlsWeth;
  address public plsWethCheckpointer;

  address public stakedEsPlsTracker;
  address public bonusEsPlsTracker;
  address public esPlsCheckpointer;

  IBonusTracker public mpPlsTracker;
  address public mpPlsCheckpointer;

  EnumerableSetUpgradeable.AddressSet private callbacks;

  address public kicker;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _mpPls,
    address _esPls,
    TrackerSet memory _plsTracker,
    TrackerSet memory _plsWethTracker,
    TrackerSet memory _esPlsTracker,
    address _mpPlsTracker,
    address _mpPlsCheckpointer
  ) public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    __Pausable_init();
    __ReentrancyGuard_init();

    mpPls = _mpPls;
    esPls = _esPls;

    stakedPlsTracker = _plsTracker.staked;
    bonusPlsTracker = _plsTracker.bonus;
    lockedPls = ILockedToken(_plsTracker.locked);
    plsCheckpointer = _plsTracker.checkpointer;

    stakedPlsWethTracker = _plsWethTracker.staked;
    bonusPlsWethTracker = _plsWethTracker.bonus;
    lockedPlsWeth = ILockedToken(_plsWethTracker.locked);
    plsWethCheckpointer = _plsWethTracker.checkpointer;

    stakedEsPlsTracker = _esPlsTracker.staked;
    bonusEsPlsTracker = _esPlsTracker.bonus;
    esPlsCheckpointer = _esPlsTracker.checkpointer;

    mpPlsTracker = IBonusTracker(_mpPlsTracker);
    mpPlsCheckpointer = _mpPlsCheckpointer;
  }

  /// @dev need to delegate to self to reflect voting power
  function delegateToSelf() external nonReentrant whenNotPaused {
    ICheckpointer(plsCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
    ICheckpointer(plsWethCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
    ICheckpointer(esPlsCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
    ICheckpointer(mpPlsCheckpointer).delegateOnBehalf(msg.sender, msg.sender);
  }

  function toggleAutoExtend(ILockedToken _token) external nonReentrant whenNotPaused {
    ILockedToken(_token).toggleAutoExtendOnBehalf(msg.sender);
  }

  function stakeAndLockPls(uint _amount) external nonReentrant whenNotPaused {
    uint len = callbacks.length();
    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionBefore(msg.sender, PlutusRouterV2.stakeAndLockPls.selector);
      unchecked {
        ++i;
      }
    }
    _autoExtendExpiredLocks(msg.sender);

    _stake(msg.sender, msg.sender, pls, _amount, stakedPlsTracker, bonusPlsTracker, plsCheckpointer);
    lockedPls.lock(msg.sender, msg.sender, _amount);

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionAfter(msg.sender, PlutusRouterV2.stakeAndLockPls.selector);
      unchecked {
        ++i;
      }
    }
  }

  function unlockAndUnstakePls() external nonReentrant whenNotPaused {
    _unlockAndUnstakePls(msg.sender);
  }

  function stakeAndLockPlsWeth(uint _amount) external nonReentrant whenNotPaused {
    uint len = callbacks.length();
    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionBefore(
        msg.sender,
        PlutusRouterV2.stakeAndLockPlsWeth.selector
      );
      unchecked {
        ++i;
      }
    }

    _autoExtendExpiredLocks(msg.sender);

    _stake(msg.sender, msg.sender, plsWeth, _amount, stakedPlsWethTracker, bonusPlsWethTracker, plsWethCheckpointer);
    lockedPlsWeth.lock(msg.sender, msg.sender, _amount);

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionAfter(msg.sender, PlutusRouterV2.stakeAndLockPlsWeth.selector);
      unchecked {
        ++i;
      }
    }
  }

  function boot(address[] memory _pls, address[] memory _plsWeth) external nonReentrant whenNotPaused {
    if (kicker != msg.sender) revert UNAUTHORIZED('PlutusRouter: !auth');
    uint _plsLen = _pls.length;
    for (uint i; i < _plsLen; ) {
      _unlockAndUnstakePls(_pls[i]);

      unchecked {
        ++i;
      }
    }

    uint _plsWethLen = _plsWeth.length;
    for (uint i; i < _plsWethLen; ) {
      _unlockAndUnstakePlsWeth(_plsWeth[i]);

      unchecked {
        ++i;
      }
    }
  }

  function unlockAndUnstakePlsWeth() external nonReentrant whenNotPaused {
    _unlockAndUnstakePlsWeth(msg.sender);
  }

  function stakeEsPls(uint _amount) external nonReentrant whenNotPaused {
    uint len = callbacks.length();
    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionBefore(msg.sender, PlutusRouterV2.stakeEsPls.selector);
      unchecked {
        ++i;
      }
    }
    _autoExtendExpiredLocks(msg.sender);

    _stake(msg.sender, msg.sender, esPls, _amount, stakedEsPlsTracker, bonusEsPlsTracker, esPlsCheckpointer);

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionAfter(msg.sender, PlutusRouterV2.stakeEsPls.selector);
      unchecked {
        ++i;
      }
    }
  }

  function unstakeEsPls(uint _amount) external nonReentrant whenNotPaused {
    uint len = callbacks.length();
    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionBefore(msg.sender, PlutusRouterV2.unstakeEsPls.selector);
      unchecked {
        ++i;
      }
    }

    _autoExtendExpiredLocks(msg.sender);

    _unstake(msg.sender, esPls, _amount, true, stakedEsPlsTracker, bonusEsPlsTracker, esPlsCheckpointer);

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionAfter(msg.sender, PlutusRouterV2.unstakeEsPls.selector);
      unchecked {
        ++i;
      }
    }
  }

  /** PERIPHERAL */
  function claimAndStakeMpPls() external nonReentrant whenNotPaused {
    uint len = callbacks.length();
    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionBefore(msg.sender, PlutusRouterV2.claimAndStakeMpPls.selector);
      unchecked {
        ++i;
      }
    }
    _autoExtendExpiredLocks(msg.sender);

    _claimAllAndStakeMpPls(msg.sender);

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionAfter(msg.sender, PlutusRouterV2.claimAndStakeMpPls.selector);
      unchecked {
        ++i;
      }
    }
  }

  function claimEsPls() external nonReentrant whenNotPaused {
    _autoExtendExpiredLocks(msg.sender);

    // add new staked trackers here
    IRewardTracker(stakedPlsTracker).claimForAccount(msg.sender, msg.sender);
    IRewardTracker(stakedPlsWethTracker).claimForAccount(msg.sender, msg.sender);
    IRewardTracker(stakedEsPlsTracker).claimForAccount(msg.sender, msg.sender);
  }

  /** PRIVATE */
  function _unlockAndUnstakePlsWeth(address _user) private {
    if (lockedPlsWeth.isAutoextendDisabled(_user) == false) revert FAILED('PlutusRouter: Auto-extend is enabled');
    uint len = callbacks.length();

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionBefore(_user, PlutusRouterV2.unlockAndUnstakePlsWeth.selector);
      unchecked {
        ++i;
      }
    }

    uint256 _withdrawn = uint256(lockedPlsWeth.withdrawExpiredLocksOnBehalf(_user, _user));
    _unstake(_user, plsWeth, _withdrawn, true, stakedPlsWethTracker, bonusPlsWethTracker, plsWethCheckpointer);

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionAfter(_user, PlutusRouterV2.unlockAndUnstakePlsWeth.selector);
      unchecked {
        ++i;
      }
    }
  }

  function _unlockAndUnstakePls(address _user) private {
    if (lockedPls.isAutoextendDisabled(_user) == false) revert FAILED('PlutusRouter: Auto-extend is enabled');
    uint len = callbacks.length();

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionBefore(_user, PlutusRouterV2.unlockAndUnstakePls.selector);
      unchecked {
        ++i;
      }
    }

    uint256 _withdrawn = uint256(lockedPls.withdrawExpiredLocksOnBehalf(_user, _user));
    _unstake(_user, pls, _withdrawn, true, stakedPlsTracker, bonusPlsTracker, plsCheckpointer);

    for (uint i; i < len; ) {
      IPlutusRouterCallback(callbacks.at(i)).handleActionAfter(_user, PlutusRouterV2.unlockAndUnstakePls.selector);
      unchecked {
        ++i;
      }
    }
  }

  function _autoExtendExpiredLocks(address _account) private {
    // add new locked tokens here
    lockedPls.processExpiredLocksOnBehalf(_account);
    lockedPlsWeth.processExpiredLocksOnBehalf(_account);
  }

  function _claimAllAndStakeMpPls(address _account) private returns (uint256 _totalClaimedAmount) {
    // add new bonus trackers here
    _totalClaimedAmount += _claimAndStakeMpPlsFor(_account, bonusPlsTracker);
    _totalClaimedAmount += _claimAndStakeMpPlsFor(_account, bonusPlsWethTracker);
    _totalClaimedAmount += _claimAndStakeMpPlsFor(_account, bonusEsPlsTracker);
  }

  function _claimAndStakeMpPlsFor(address _account, address _rewardTracker) private returns (uint256 _claimedAmount) {
    _claimedAmount = IRewardTracker(_rewardTracker).claimForAccount(_account, _account);

    if (_claimedAmount > 0) {
      mpPlsTracker.stakeForAccount(_account, _account, _rewardTracker, _claimedAmount);
      ICheckpointer(mpPlsCheckpointer).increment(_account, _claimedAmount);
    }
  }

  function _unstake(
    address _account,
    address _token,
    uint256 _amount,
    bool _shouldReduceMp,
    address _rewardTracker,
    address _bonusTracker,
    address _checkpointer
  ) private {
    if (_amount == 0) revert FAILED('PlutusRouter: invalid amount');

    // total staked bonus for account from all sources
    uint256 _accountStakedMpsPls = IRewardTracker(bonusPlsTracker).stakedSynthAmounts(_account) +
      IRewardTracker(bonusPlsWethTracker).stakedSynthAmounts(_account) +
      IRewardTracker(bonusEsPlsTracker).stakedSynthAmounts(_account);

    IRewardTracker(_bonusTracker).unstakeForAccount(_account, _rewardTracker, _amount, _account);
    IRewardTracker(_rewardTracker).unstakeForAccount(_account, _token, _amount, _account);
    ICheckpointer(_checkpointer).decrement(_account, _amount);

    emit Unstake(_account, _token, _amount);

    if (_shouldReduceMp) {
      if (plsWeth == _token) {
        _amount = (_amount * IBaseDistributor(IRewardTracker(bonusPlsWethTracker).distributor()).getRate()) / 1e4;
      }
      _reduceMps(_account, _accountStakedMpsPls, _amount);
    }
  }

  function _reduceMps(address _account, uint256 _accountStakedMpsPls, uint256 _amountUnstaked) private {
    // claim and stake all Mps
    _claimAllAndStakeMpPls(_account);
    uint256 _totalStakedMpPls = mpPlsTracker.stakedAmounts(_account);

    if (_totalStakedMpPls > 0) {
      // calculate reduction amount
      uint256 _reductionAmount = (_totalStakedMpPls * _amountUnstaked) / _accountStakedMpsPls;

      mpPlsTracker.unstakeForAccount(_account, _reductionAmount, _account);
      ICheckpointer(mpPlsCheckpointer).decrement(_account, _reductionAmount);
      IBaseMintableToken(mpPls).burn(_account, _reductionAmount);
    }
  }

  function _stake(
    address _fundingAccount,
    address _account,
    address _token,
    uint256 _amount,
    address _rewardTracker,
    address _bonusTracker,
    address _checkpointer
  ) private {
    if (_amount == 0) revert FAILED('PlutusRouter: invalid amount');

    IRewardTracker(_rewardTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
    IRewardTracker(_bonusTracker).stakeForAccount(_account, _account, _rewardTracker, _amount);
    ICheckpointer(_checkpointer).increment(_account, _amount);

    emit Stake(_account, _token, _amount);
  }

  function getCallback(uint256 index) public view returns (address) {
    if (index >= callbacks.length()) {
      revert FAILED('PlutusRouter: No callback contract available at this index');
    }
    return callbacks.at(index);
  }

  function getAllCallbacks() public view returns (address[] memory) {
    return callbacks.values();
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function recoverErc20(IERC20Upgradeable _erc20, uint _amount) external onlyOwner {
    IERC20Upgradeable(_erc20).transfer(owner(), _amount);
  }

  function setKicker(address _kicker) external onlyOwner {
    kicker = _kicker;
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  function addCallback(address callback) external onlyOwner {
    bool added = callbacks.add(callback);

    if (!added) {
      revert FAILED('PlutusRouter: Callback already registered');
    }
  }

  function removeCallback(address callback) external onlyOwner {
    bool removed = callbacks.remove(callback);

    if (!removed) {
      revert FAILED('PlutusRouter: Callback not found');
    }
  }
}