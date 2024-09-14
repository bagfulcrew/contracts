// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Bagful reward interface
interface IRewardNew {
    struct UserRewardInfo {
        uint256 depositAmount;
        uint256 rewardAmount;
        uint256 rewardDebt;
        uint256 lastClaimTime;
    }

    function calculateReward(address user, uint256 depositAmount) external view returns (uint256);

    function distributeReward(address user, uint256 rewardAmount) external;

    function updateUserState(address user, uint256 amount, bool deposit) external;

    function retireReward() external;

    function isRetired() external view returns (bool);

    function isSettledIncome() external view returns (bool);

    function getUserRewardInfo(address _user) external view returns (UserRewardInfo memory);

    function getRewardToken() external view returns (address);

    function updatePool() external;
}

