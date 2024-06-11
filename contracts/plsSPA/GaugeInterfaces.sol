// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IMasterBribe {
  struct BribeRewardData {
    address token;
    uint256 amount;
  }

  function claimBribe(address _gAddr) external;

  function computeBribe(address _gAddr, address _user)
    external
    view
    returns (
      BribeRewardData[] memory rewards,
      uint256 t0,
      uint256 t
    );

  function getAllBribeTokens(address _gAddr) external view returns (address[] memory);
}

interface IGaugeController {
  function voteForGaugeWeight(address _gAddr, uint256 _userWeight) external;

  function timeTotal() external view returns (uint256);

  function getGaugeList() external view returns (address[] memory);

  function getUserVotesWtForGauge(address _gAddr, uint256 _time) external view returns (uint256);

  function getGaugeWeight(address _gAddr) external view returns (uint256);

  function getGaugeWeight(address _gAddr, uint256 _time) external view returns (uint256);

  function gaugeRelativeWeight(address _gAddr) external view returns (uint256);

  function gaugeRelativeWeight(address _gAddr, uint256 _time) external view returns (uint256);

  function getTotalWeight() external view returns (uint256);

  function getTypeWeight(uint128 _gType) external view returns (uint256);

  function getWeightsSumPerType(uint128 _gType) external view returns (uint256);

  function gaugeType(address _gAddr) external view returns (uint128);

  function gaugeBribe(address _gAddr) external view returns (address);

  function userVotePower(address _user) external view returns (uint256);

  function userVoteData(address _user, address _gAddr)
    external
    view
    returns (
      uint256 slope,
      uint256 power,
      uint256 end,
      uint256 voteTime
    );
}

interface IBribe {
  function claimRewards(address _user) external;

  function getAllBribeTokens() external view returns (address[] memory);

  function computeRewards(address _user) external view returns (uint256[] memory);
}

interface ISpaStakerGaugeHandler {
  struct RewardInfo {
    address gauge;
    IMasterBribe.BribeRewardData[] rewardData;
  }

  function pendingRewards(address _user) external view returns (RewardInfo[] memory rewardInfo);

  function voteForGaugeWeight(address _gAddr, uint256 _userWeight) external;

  function claimAndTransferBribes() external returns (IMasterBribe.BribeRewardData[] memory rwData);
}