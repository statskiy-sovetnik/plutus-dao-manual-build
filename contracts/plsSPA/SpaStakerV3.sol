// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IStaker, IveSPA, IRewardDistributor_v2 } from './interfaces.sol';
import { IGaugeController, ISpaStakerGaugeHandler, IMasterBribe } from './GaugeInterfaces.sol';

contract SpaStakerV3 is Initializable, OwnableUpgradeable, UUPSUpgradeable, IStaker, ISpaStakerGaugeHandler {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  uint256 private constant WEEK = 7 * 86400;
  uint256 public constant MAXTIME = 4 * 365 * 86400;
  IERC20 public constant token = IERC20(0x5575552988A3A80504bBaeB1311674fCFd40aD4B);
  address public constant escrow = 0x2e2071180682Ce6C247B1eF93d382D509F5F6A17;
  IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x895D0A8A439616e737Dcfb3BD59C552CBA05251c);
  IMasterBribe public constant MASTER_BRIBE = IMasterBribe(0x430B83b71C3EBed371D481DEC29F254BAF4fFD25);
  address public constant BRIBE_DISTRO = 0x24F11B6e5B21CAb23a8324438a4156FB96eBB0A5;

  address public depositor;
  address public operator;
  uint256 public unlockTime;
  address public voter;
  EnumerableSetUpgradeable.AddressSet private rewardTokens;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    token.approve(escrow, type(uint256).max);
    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function stake(uint256 _amount) external {
    if (msg.sender != depositor) revert UNAUTHORIZED();

    // increase amount
    IveSPA(escrow).increaseAmount(uint128(_amount));

    unchecked {
      uint256 unlockAt = block.timestamp + MAXTIME;
      uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

      // increase time too if over 1 week buffer
      if (unlockInWeeks - unlockTime >= 1) {
        IveSPA(escrow).increaseUnlockTime(unlockAt);
        unlockTime = unlockInWeeks;
      }
    }
  }

  function maxLock() external returns (bool) {
    if (msg.sender != operator) revert UNAUTHORIZED();

    unchecked {
      uint256 unlockAt = block.timestamp + MAXTIME;
      uint256 unlockInWeeks = (unlockAt / WEEK) * WEEK;

      IveSPA(escrow).increaseUnlockTime(unlockAt);
      unlockTime = unlockInWeeks;
    }

    return true;
  }

  function claimFees(
    address _distroContract,
    address _token,
    address _claimTo
  ) external returns (uint256) {
    if (msg.sender != operator) revert UNAUTHORIZED();
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
    IRewardDistributor_v2(_distroContract).claim(false);
    uint256 _balanceAfter = IERC20(_token).balanceOf(address(this));

    uint256 feeAmount = _balanceAfter - _balanceBefore;

    if (isNotZero(feeAmount)) {
      IERC20(_token).transfer(_claimTo, feeAmount);
    }

    return feeAmount;
  }

  /** CHECKS */
  function isNotZero(uint256 _num) private pure returns (bool result) {
    assembly {
      result := gt(_num, 0)
    }
  }

  function isZero(uint256 _num) private pure returns (bool result) {
    assembly {
      result := iszero(_num)
    }
  }

  function _unsafeInc(uint256 x) private pure returns (uint256) {
    unchecked {
      return x + 1;
    }
  }

  /** VOTER FUNCTIONS */
  function pendingRewards(address _user) external view returns (RewardInfo[] memory rewardInfo) {
    address[] memory gaugeList = GAUGE_CONTROLLER.getGaugeList();

    uint256 len = gaugeList.length;
    rewardInfo = new RewardInfo[](len);

    for (uint256 i; i < len; i = _unsafeInc(i)) {
      (IMasterBribe.BribeRewardData[] memory rwData, , ) = MASTER_BRIBE.computeBribe(gaugeList[i], address(_user));

      rewardInfo[i] = RewardInfo({ gauge: gaugeList[i], rewardData: rwData });
    }
  }

  function getRewardTokens() public view returns (address[] memory rewardTokenArr) {
    uint256 len = rewardTokens.length();
    rewardTokenArr = new address[](len);

    for (uint256 i; i < len; i = _unsafeInc(i)) {
      rewardTokenArr[i] = rewardTokens.at(i);
    }
  }

  function claimAndTransferBribes() external returns (IMasterBribe.BribeRewardData[] memory consolidatedRewardsData) {
    if (msg.sender != BRIBE_DISTRO) revert UNAUTHORIZED();

    address[] memory gaugeList = GAUGE_CONTROLLER.getGaugeList();
    uint256 len = gaugeList.length;

    // Claim Bribes and record reward tokens
    for (uint256 i; i < len; i = _unsafeInc(i)) {
      (, uint256 power, , ) = GAUGE_CONTROLLER.userVoteData(address(this), gaugeList[i]);

      // claim bribe if voted
      if (power > 0) {
        // store reward tokens so we can consolidate and transfer at the end
        address[] memory _tokens = MASTER_BRIBE.getAllBribeTokens(gaugeList[i]);
        for (uint256 t; t < _tokens.length; t++) {
          // add reward token to set
          rewardTokens.add(_tokens[t]);
        }

        MASTER_BRIBE.claimBribe(gaugeList[i]);
      }
    }

    // consolidated transfer
    uint256 rewardTokensLen = rewardTokens.length();
    consolidatedRewardsData = new IMasterBribe.BribeRewardData[](rewardTokensLen);

    for (uint256 i; i < rewardTokensLen; i = _unsafeInc(i)) {
      address _token = rewardTokens.at(i);
      uint256 _bal = IERC20(_token).balanceOf(address(this));

      if (_bal > 0) {
        consolidatedRewardsData[i] = IMasterBribe.BribeRewardData({ token: _token, amount: _bal });
        IERC20(_token).transfer(BRIBE_DISTRO, _bal);
      }
    }
  }

  function voteForGaugeWeight(address _gAddr, uint256 _userWeight) external {
    if (msg.sender != voter) revert UNAUTHORIZED();
    GAUGE_CONTROLLER.voteForGaugeWeight(_gAddr, _userWeight);
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  //
  function removeRewardTokens(address _token) external onlyOwner {
    if (rewardTokens.contains(_token)) {
      rewardTokens.remove(_token);
    } else {
      revert FAILED();
    }
  }

  function recoverErc20(IERC20 _erc20, uint256 _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function release() external onlyOwner {
    emit Release();
    IveSPA(escrow).withdraw();
  }

  function setOperator(address _newOperator) external onlyOwner {
    emit OperatorChanged(_newOperator, operator);
    operator = _newOperator;
  }

  function setDepositor(address _newDepositor) external onlyOwner {
    emit DepositorChanged(_newDepositor, depositor);
    depositor = _newDepositor;
  }

  function setVoter(address _newVoter) external onlyOwner {
    emit VoterChanged(_newVoter, voter);
    voter = _newVoter;
  }

  event Release();
  event OperatorChanged(address indexed _new, address _old);
  event DepositorChanged(address indexed _new, address _old);
  event VoterChanged(address indexed _new, address _old);

  error UNAUTHORIZED();
  error FAILED();
  error INVALID_FEE();
}