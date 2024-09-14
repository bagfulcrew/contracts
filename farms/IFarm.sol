// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Bagful farm interface
interface IFarm {
    // User info structure
    struct UserInfo {
        uint256 underlyingAmount;
        uint256 cTokenAmount;
        uint256 lastDepositTime;
    }

    struct UserRewardInfo {
        address rewardAddress;
        address rewardToken;
        uint256 rewardAmount;
        uint256 claimAmount;
        uint256 lastClaimTime;
    }

    function getPoolTvl() external view returns (uint256);

    function getUserAllRewards(address _user) external view returns (uint256, IFarm.UserRewardInfo[] memory);
}
