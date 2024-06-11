// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IChefIncentivesController {
  function claimAll(address _user) external;

  function allPendingRewards(address _user) external view returns (uint256 pending);
}

interface ILendingPool {
  /**
   * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
   * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
   * @param asset The address of the underlying asset to deposit
   * @param amount The amount to be deposited
   * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
   *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
   *   is a different wallet
   * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
   *   0 if the action is executed directly by the user, without any middle-man
   **/
  function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

  function depositWithAutoDLP(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

  /**
   * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
   * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
   * @param asset The address of the underlying asset to withdraw
   * @param amount The underlying amount to be withdrawn
   *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
   * @param to Address that will receive the underlying, same as msg.sender if the user
   *   wants to receive it on his own wallet, or a different address if the beneficiary is a
   *   different wallet
   * @return The final amount withdrawn
   **/
  function withdraw(address asset, uint256 amount, address to) external returns (uint256);

  /**
   * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
   * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
   * corresponding debt token (StableDebtToken or VariableDebtToken)
   * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
   *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
   * @param asset The address of the underlying asset to borrow
   * @param amount The amount to be borrowed
   * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
   * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
   *   0 if the action is executed directly by the user, without any middle-man
   * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
   * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
   * if he has been given credit delegation allowance
   **/
  function borrow(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    uint16 referralCode,
    address onBehalfOf
  ) external;

  /**
   * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
   * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
   * @param asset The address of the borrowed underlying asset previously borrowed
   * @param amount The amount to repay
   * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
   * @param rateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
   * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
   * user calling the function if he wants to reduce/remove his own debt, or the address of any other
   * other borrower whose debt should be removed
   * @return The final amount repaid
   **/
  function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);

  /**
   * @dev Returns the user account data across all the reserves
   * @param user The address of the user
   * @return totalCollateralETH the total collateral in ETH of the user
   * @return totalDebtETH the total debt in ETH of the user
   * @return availableBorrowsETH the borrowing power left of the user
   * @return currentLiquidationThreshold the liquidation threshold of the user
   * @return ltv the loan to value of the user
   * @return healthFactor the current health factor of the user
   **/
  function getUserAccountData(
    address user
  )
    external
    view
    returns (
      uint256 totalCollateralETH,
      uint256 totalDebtETH,
      uint256 availableBorrowsETH,
      uint256 currentLiquidationThreshold,
      uint256 ltv,
      uint256 healthFactor
    );
}

interface ISharedStruct {
  struct LockedBalance {
    uint256 amount;
    uint256 unlockTime;
    uint256 multiplier;
    uint256 duration;
  }
}

interface IChefIncentivesHandler is ISharedStruct {
  struct EarnedBalance {
    uint256 amount;
    uint256 unlockTime;
    uint256 penalty;
  }

  /**
   * @notice Withdraw individual unlocked balance and earnings, optionally claim pending rewards.
   */
  function individualEarlyExit(bool claimRewards, uint256 unlockTime) external;

  /**
   * @notice Withdraw tokens from earnings and unlocked.
   * @dev First withdraws unlocked tokens, then earned tokens. Withdrawing earned tokens
   *  incurs a 50% penalty which is distributed based on locked balances.
   */
  function withdraw(uint256 amount) external;

  /**
   * @notice Withdraw full unlocked balance and earnings, optionally claim pending rewards.
   */
  function exit(bool claimRewards) external;

  /**
   * @notice Earnings which is locked yet
   * @dev Earned balances may be withdrawn immediately for a 50% penalty.
   * @return total earnings
   * @return unlocked earnings
   * @return earningsData which is an array of all infos
   */

  function earnedBalances(
    address user
  ) external view returns (uint256 total, uint256 unlocked, EarnedBalance[] memory earningsData);

  /**
   * @notice Final balance received and penalty balance paid by user upon calling exit.
   * @dev This is earnings, not locks.
   */
  function withdrawableBalance(
    address user
  ) external view returns (uint256 amount, uint256 penaltyAmount, uint256 burnAmount);
}

interface IProtocolRewardsHandler is ISharedStruct {
  struct RewardData {
    address token;
    uint256 amount;
  }

  function stake(uint256 amount, address onBehalfOf, uint256 typeIndex) external;

  function setRelock(bool _status) external;

  function setDefaultRelockTypeIndex(uint256 _index) external;

  function withdrawExpiredLocksFor(address _address) external returns (uint256);

  function withdrawExpiredLocksForWithOptions(
    address _address,
    uint256 _limit,
    bool _ignoreRelock
  ) external returns (uint256);

  function getReward(address[] memory _rewardTokens) external;

  /** VIEWS */
  function claimableRewards(address account) external view returns (RewardData[] memory rewardsData);

  /**
   * @notice Returns all locks of a user.
   */
  function lockInfo(address user) external view returns (LockedBalance[] memory);

  /**
   * @notice Information on a user's lockings
   * @return total balance of locks
   * @return unlockable balance
   * @return locked balance
   * @return lockedWithMultiplier
   * @return lockData which is an array of locks
   */
  function lockedBalances(
    address user
  )
    external
    view
    returns (
      uint256 total,
      uint256 unlockable,
      uint256 locked,
      uint256 lockedWithMultiplier,
      LockedBalance[] memory lockData
    );
}

// MultiFeeDistribution does 2 things: handle protocol fee distro + handle chef rewards distro
interface IMultiFeeDistribution is IChefIncentivesHandler, IProtocolRewardsHandler {
  struct Reward {
    uint256 periodFinish;
    uint256 rewardPerSecond;
    uint256 lastUpdateTime;
    uint256 rewardPerTokenStored;
    // tracks already-added balances to handle accrued interest in aToken rewards
    // for the stakingToken this value is unused and will always be 0
    uint256 balance;
  }

  function rewardPerToken(address _rewardToken) external view returns (uint256 rptStored);

  function rewardData(address _rewardToken) external view returns (Reward memory);

  function userRewardPerTokenPaid(address _user, address _rewardToken) external view returns (uint256 _rpt);

  function rewards(address _user, address _rewardToken) external view returns (uint256 _amount);

  ///@dev BUGGY
  /**
   * @notice Total balance of an account, including unlocked, locked and earned tokens.
   */
  function totalBalance(address user) external view returns (uint256 amount);
}