pragma solidity 0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import './interfaces.sol';
import './GaugeInterfaces.sol';

interface IPlsSpaVoter {
  struct RewardInfo {
    address gauge;
    address bribe;
    address[] tokens;
    uint256[] rewards;
  }

  struct VoteInfo {
    address gauge;
    uint256 weight;
    uint256 power;
    uint256 userWeight;
  }

  error FAILED(string);
}

contract PlsSpaVoter is IPlsSpaVoter, Ownable {
  ISpaStakerGaugeHandler__ public constant SPA_STAKER =
    ISpaStakerGaugeHandler__(0x46ac70bf830896EEB2a2e4CBe29cD05628824928);
  IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x895D0A8A439616e737Dcfb3BD59C552CBA05251c);
  IveSPA public constant VESPA = IveSPA(0x2e2071180682Ce6C247B1eF93d382D509F5F6A17);
  address public bribeDistro;

  /** VIEW FUNCTIONS */
  function voteStats(address _user)
    external
    view
    returns (
      uint256 totalUserWeight,
      uint256 totalWeight,
      VoteInfo[] memory voteInfo
    )
  {
    totalUserWeight = VESPA.balanceOf(_user, GAUGE_CONTROLLER.timeTotal());
    totalWeight = GAUGE_CONTROLLER.getTotalWeight();

    address[] memory gaugeList = GAUGE_CONTROLLER.getGaugeList();
    voteInfo = new VoteInfo[](gaugeList.length);

    for (uint256 i; i < gaugeList.length; i = _unsafeInc(i)) {
      (, uint256 power, , ) = GAUGE_CONTROLLER.userVoteData(_user, gaugeList[i]);
      uint256 weight = GAUGE_CONTROLLER.getGaugeWeight(gaugeList[i]);

      unchecked {
        voteInfo[i] = VoteInfo({
          gauge: gaugeList[i],
          power: power,
          weight: weight,
          userWeight: (power * totalUserWeight) / 1e4
        });
      }
    }
  }

  function pendingRewards(address _user) external view returns (RewardInfo[] memory rewardInfo) {
    address[] memory gaugeList = GAUGE_CONTROLLER.getGaugeList();
    rewardInfo = new RewardInfo[](gaugeList.length);

    for (uint256 i; i < gaugeList.length; i = _unsafeInc(i)) {
      address bribe = GAUGE_CONTROLLER.gaugeBribe(gaugeList[i]);

      rewardInfo[i] = RewardInfo({
        gauge: gaugeList[i],
        bribe: bribe,
        tokens: IBribe(bribe).getAllBribeTokens(),
        rewards: IBribe(bribe).computeRewards(_user)
      });
    }
  }

  function _unsafeInc(uint256 x) private pure returns (uint256) {
    unchecked {
      return x + 1;
    }
  }

  /** OWNER FUNCTIONS */
  /**
    Retrieve stuck funds
   */
  function retrieve(IERC20 _erc20) external onlyOwner {
    if ((address(this).balance) != 0) {
      Address.sendValue(payable(owner()), address(this).balance);
    }

    _erc20.transfer(owner(), _erc20.balanceOf(address(this)));
  }

  function voteForGaugeWeight(address _gAddr, uint256 _userWeight) external onlyOwner {
    ISpaStakerGaugeHandler__(SPA_STAKER).voteForGaugeWeight(_gAddr, _userWeight);
  }

  ///@dev Must have already claimed reward by calling bribe.claimRewards()
  function transferReward(address _token) external onlyOwner {
    if (bribeDistro == address(0)) revert FAILED('!addr');
    ISpaStakerGaugeHandler__(SPA_STAKER).transferReward(_token, bribeDistro);
  }

  function setBribeDistro(address _bribeDistro) external onlyOwner {
    bribeDistro = _bribeDistro;
  }
}