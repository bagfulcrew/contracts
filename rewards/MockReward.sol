// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../comm/TransferHelper.sol";
import "./IRewardNew.sol";
import "./IMendiCToken.sol";
import "../farms/IFarm.sol";

contract MockReward is IRewardNew, Ownable {
    IERC20 public rewardToken;
    uint256 public rewardApyRate;
    bool public retired;
    bool public settledIncome;
    // ETH token address
    address public ethAddr;

    mapping(address => UserRewardInfo) public userRewards;

    address public poolAddress;

    modifier onlyPool() {
        require(msg.sender == poolAddress, "Caller invalid");
        _;
    }

    constructor(
        address _rewardToken,
        address _ethAddr,
        address _farmAddr,
        address _owner
    ) Ownable(_owner){
        rewardApyRate = 5;
        poolAddress = _farmAddr;
        rewardToken = IERC20(_rewardToken);
        ethAddr = _ethAddr;
        retired = false;
        settledIncome = true;
    }

    function setFarmAddress(address _farmAddress) external onlyOwner {
        require(_farmAddress != address(0), "Farm address cannot be zero address");
        poolAddress = _farmAddress;
    }

    function getRewardToken() external view returns (address) {
        return address(rewardToken);
    }

    function calculateReward(address user, uint256 depositAmount) public view returns (uint256) {
        if (retired || userRewards[user].lastClaimTime == 0) {
            return 0;
        }

        uint256 duration = block.timestamp - userRewards[user].lastClaimTime;
        return (depositAmount * rewardApyRate * duration) / (100 * 365 days);
    }

    function distributeReward(address user, uint256 rewardAmount) external override onlyPool {
        if (rewardAmount > 0 && !retired) {
            userRewards[user].rewardAmount += rewardAmount;

            if (address(rewardToken) == ethAddr) {
                TransferHelper.safeTransferETH(user, rewardAmount);
            } else {
                TransferHelper.safeTransfer(address(rewardToken), user, rewardAmount);
            }
        }

        userRewards[user].lastClaimTime = block.timestamp;
    }

    function updateUserState(address user, uint256 amount, bool deposit) external override onlyPool {
        if (!retired) {
            if (deposit) {
                userRewards[user].depositAmount += amount;
            } else {
                userRewards[user].depositAmount -= amount;
            }
        }
    }

    function getUserRewardInfo(address _user) external view returns (UserRewardInfo memory) {
        return userRewards[_user];
    }

    function retireReward() external override onlyOwner {
        retired = true;
    }

    function isRetired() external view override returns (bool) {
        return retired;
    }

    function isSettledIncome() external view override returns (bool) {
        return settledIncome;
    }

    function updatePool() external {

    }
}
