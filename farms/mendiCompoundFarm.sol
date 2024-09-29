// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../rewards/IMendiCToken.sol";
import "../comm/TransferHelper.sol";
import "../rewards/IRewardNew.sol";
import "./IFarm.sol";

contract BagfulMendiCompoundFarm is Initializable, OwnableUpgradeable,
ReentrancyGuardUpgradeable, PausableUpgradeable, IFarm {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Custom errors
    error RewardTokenExisted(address token);

    // Events
    /// @notice Emitted when add extra reward token
    event AddExtraRewardToken(address indexed rewardToken);

    /// @notice Emitted when remove extra reward token
    event RemoveExtraRewardToken(address indexed rewardToken);

    /// @notice Emitted when user deposit assets
    event Deposit(address indexed user, uint256 underlyingAmount, uint256 cTokenAmount);

    /// @notice Emitted when user deposit assets
    event Withdraw(address indexed user, uint256 withdrawAmount);

    /// @notice Emitted when set the start timestamp
    event EventSetStartTimestamp(uint256 indexed _startTime);

    /// @notice Emitted when set the start timestamp
    event EventSetMendiCToken(address indexed _cTokenAddr);

    /// @notice Emitted when start to mint
    event EventStartMinting(uint256 timestamp);

    // Assets token
    IERC20 public assetToken;

    // Mendi cToken
    IMendiCToken public mendiCToken;

    // Wrapped/ETH token address
    address public ethAddr;

    // Total deposits
    uint256 public totalDeposits;

    // User address list
    EnumerableSet.AddressSet private userAddrList;

    // Farm rewards
    IRewardNew[] public extraRewards;

    // Users map
    mapping(address => UserInfo) public userInfoMap;

    // Farm start timestamp
    uint256 public startTimestamp;

    // Reserved storage acts as a buffer between the last variable and the end of the slot
    uint256[50] private __gap;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the farm
    function initialize(
        address _assets,
        address _mendiCToken,
        address _ethAddr
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        require(_assets != address(0), "Invalid assets address");
        require(_mendiCToken != address(0), "Invalid cToken address");

        assetToken = IERC20(_assets);
        mendiCToken = IMendiCToken(_mendiCToken);
        ethAddr = _ethAddr;
    }

    /// @notice Add new reward token to pool
    /// @param _rewardTokenAddr The new reward token
    function addExtraReward(address _rewardTokenAddr) external onlyOwner {
        require(_rewardTokenAddr != address(0), "Invalid reward address");

        uint256 len = extraRewards.length;
        for (uint256 i = 0; i < len; i++) {
            if (address(extraRewards[i]) == _rewardTokenAddr) {
                revert RewardTokenExisted(_rewardTokenAddr);
            }
        }

        extraRewards.push(IRewardNew(_rewardTokenAddr));
        emit AddExtraRewardToken(_rewardTokenAddr);
    }

    /// @notice Remove the reward token from pool
    /// @param _rewardTokenAddr The reward token to remove
    function removeExtraReward(address _rewardTokenAddr) external onlyOwner {
        require(_rewardTokenAddr != address(0), "Invalid reward address");

        address[] memory userList = userAddrList.values();

        for (uint256 i = 0; i < extraRewards.length; i++) {
            if (address(extraRewards[i]) == _rewardTokenAddr) {
                IRewardNew _reward = IRewardNew(_rewardTokenAddr);

                for (uint256 j = 0; j < userList.length; j++) {
                    UserInfo storage userInfo = userInfoMap[userList[j]];
                    uint256 rewardAmount = _reward.calculateReward(userList[j],
                        extraRewards[i].isSettledIncome() ? userInfo.underlyingAmount : 0);

                    // Liquidity reward
                    if (extraRewards[i].isSettledIncome() == false) {
                        extraRewards[i].updatePool();
                    }

                    if (rewardAmount > 0) {
                        _reward.distributeReward(userList[j], rewardAmount);
                    }
                }

                extraRewards[i] = extraRewards[extraRewards.length - 1];
                extraRewards.pop();

                break;
            }
        }

        emit RemoveExtraRewardToken(_rewardTokenAddr);
    }

    /// @notice Get the total reward to distribute
    function getRemovalRewardAmounts(address _rewardTokenAddr) external onlyOwner view returns (uint256){
        require(_rewardTokenAddr != address(0), "Invalid reward address");

        uint256 totalRewardsToDistribute = 0;

        address[] memory userList = userAddrList.values();

        // Calculate total rewards to distribute
        for (uint256 i = 0; i < extraRewards.length; i++) {
            if (address(extraRewards[i]) == _rewardTokenAddr) {
                IRewardNew _reward = IRewardNew(_rewardTokenAddr);

                for (uint256 j = 0; j < userList.length; j++) {
                    UserInfo storage userInfo = userInfoMap[userList[j]];
                    totalRewardsToDistribute += _reward.calculateReward(userList[j],
                        extraRewards[i].isSettledIncome() ? userInfo.underlyingAmount : 0);
                }
                break;
            }
        }

        return totalRewardsToDistribute;
    }

    /// @notice Deposit assets to the farm
    /// @param _amount The amount of assets to deposit
    function deposit(uint256 _amount) external payable nonReentrant whenNotPaused {
        require(startTimestamp > 0, "Farm: mining not start!!");

        UserInfo storage userInfo = userInfoMap[msg.sender];

        // Distribute rewards to user
        distributeAllRewards(msg.sender);

        // process WETH
        if (address(assetToken) == ethAddr) {
            require(_amount == 0, "Deposit invalid token");

            if (msg.value > 0) {
                _amount = _amount + msg.value;
            }
        } else {
            require(msg.value == 0, "Deposit invalid token");
            if (_amount > 0) {
                uint256 _beforeBalance = assetToken.balanceOf(address(this));
                TransferHelper.safeTransferFrom(address(assetToken), address(msg.sender), address(this), _amount);
                _amount = assetToken.balanceOf(address(this)) - _beforeBalance;
            }
        }

        // Calculate the cToken
        uint256 calcCToken = underlyingToCToken(_amount);

        // Save assets to Mendi
        TransferHelper.safeApprove(address(assetToken), address(mendiCToken), _amount);
        mendiCToken.mint(_amount);

        userInfo.underlyingAmount += _amount;
        userInfo.cTokenAmount += calcCToken;
        userInfo.lastDepositTime = block.timestamp;

        userAddrList.add(msg.sender);

        totalDeposits += _amount;

        updateAllRewards(msg.sender, _amount, true);

        emit Deposit(msg.sender, _amount, calcCToken);
    }

    /// @notice Withdraw assets from the farm
    /// @param _amount The amount of assets to withdraw
    function withdraw(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Invalid deposit amount");
        require(startTimestamp > 0, "Mining not start!!");

        UserInfo storage userInfo = userInfoMap[msg.sender];
        require(userInfo.underlyingAmount >= _amount, "Insufficient balance");

        // Distribute rewards to user
        distributeAllRewards(msg.sender);

        uint success = mendiCToken.redeemUnderlying(_amount);
        require(success == 0, "Redeem failed");

        uint256 reduceCTokenAmount = underlyingToCToken(_amount);

        if (userInfo.cTokenAmount > reduceCTokenAmount) {
            userInfo.cTokenAmount -= reduceCTokenAmount;
        } else {
            userInfo.cTokenAmount = 0;
        }

        userInfo.underlyingAmount -= _amount;
        userInfo.lastDepositTime = block.timestamp;

        totalDeposits -= _amount;

        if (address(assetToken) == ethAddr) {
            TransferHelper.safeTransferETH(msg.sender, _amount);
        } else {
            TransferHelper.safeTransfer(address(assetToken), msg.sender, _amount);
        }

        updateAllRewards(msg.sender, _amount, false);

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice Calculate the rewards and transfer to user
    /// @param _user The user address
    function harvest(address _user) external nonReentrant whenNotPaused {
        require(startTimestamp > 0, "Mining not start!!");
        require(_user != address(0), "Farm: invalid user address");

        UserInfo storage userInfo = userInfoMap[_user];
        require(userInfo.underlyingAmount > 0, "No deposit");

        for (uint256 i = 0; i < extraRewards.length; i++) {
            IRewardNew _extraReward = extraRewards[i];

            uint256 pendingRewards = extraRewards[i].calculateReward(_user,
                _extraReward.isSettledIncome() ? userInfo.underlyingAmount : 0);

            // Liquidity reward
            if (_extraReward.isSettledIncome() == false) {
                _extraReward.updatePool();
            }

            if (pendingRewards > 0) {
                _extraReward.distributeReward(_user, pendingRewards);
            }
        }
    }

    /// @notice Start to mint
    function startMining() public onlyOwner whenNotPaused {
        require(startTimestamp == 0, "Farm: mining already started");
        startTimestamp = block.timestamp;

        emit EventStartMinting(startTimestamp);
    }

    /// @notice Set the farm start timestamp
    /// @param _timestamp The farm start timestamp(seconds)
    function setStartTimestamp(uint256 _timestamp) external onlyOwner {
        require(startTimestamp == 0, "Farm: already started");
        require(_timestamp > block.timestamp, "Farm: start timestamp must be in the future");
        require(_timestamp <= block.timestamp + 30 days, "Farm: start timestamp too far in the future");

        startTimestamp = _timestamp;
        emit EventSetStartTimestamp(_timestamp);
    }

    /// @notice Return the user underlying assets balance
    function balanceOfUnderlying() external view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    /// @notice Return the user cToken balance
    function balanceOf() external view returns (uint256) {
        uint256 cTokenAmount = mendiCToken.balanceOf(address(this));
        return cTokenToUnderlying(cTokenAmount);
    }

    /// @notice Get user info
    /// @param _user The user address
    /// @return The user info
    function getUserInfo(address _user) external view returns (UserInfo memory) {
        return userInfoMap[_user];
    }

    /// @notice Get pool users
    /// @return The user list
    function getActionUserList() external onlyOwner view returns (address[] memory){
        address[] memory userList = userAddrList.values();
        return userList;
    }

    /// @notice Set the farm assets token
    /// @param _mendiCToken The mendi cToken
    function setMendiCToken(address _mendiCToken) external onlyOwner {
        require(_mendiCToken != address(0), "Invalid cToken address");
        mendiCToken = IMendiCToken(_mendiCToken);

        emit EventSetMendiCToken(_mendiCToken);
    }

    /// @notice Pause the farm
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the farm
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Distribute all of rewards to user
    /// @param _user The user address
    function distributeAllRewards(address _user) internal {
        UserInfo storage userInfo = userInfoMap[_user];

        for (uint256 i = 0; i < extraRewards.length; i++) {
            IRewardNew _extraReward = extraRewards[i];

            uint256 rewardAmount = extraRewards[i].calculateReward(_user,
                _extraReward.isSettledIncome() ? userInfo.underlyingAmount : 0);

            // Liquidity reward
            if (_extraReward.isSettledIncome() == false) {
                _extraReward.updatePool();
            }

            if (rewardAmount > 0) {
                extraRewards[i].distributeReward(_user, rewardAmount);
            }
        }
    }

    /// @notice Update all of rewards state
    /// @param _user The user address
    /// @param _amount The amount of assets
    /// @param depositFlag The deposit flag
    function updateAllRewards(address _user, uint256 _amount, bool depositFlag) internal {
        for (uint256 i = 0; i < extraRewards.length; i++) {
            if (!extraRewards[i].isRetired()) {
                if (depositFlag) {
                    extraRewards[i].updateUserState(_user, _amount, depositFlag);
                } else {
                    IRewardNew.UserRewardInfo memory userInfo = extraRewards[i].getUserRewardInfo(_user);
                    if (userInfo.depositAmount > 0) {
                        extraRewards[i].updateUserState(_user, _amount, depositFlag);
                    }
                }

            }
        }
    }

    /// @notice Get user all rewards
    /// @param _user The user address
    /// @return The user rewards information
    function getUserAllRewards(address _user) public view returns (uint256, UserRewardInfo[] memory) {
        UserInfo memory user = userInfoMap[_user];
        UserRewardInfo[] memory rewards = new UserRewardInfo[](extraRewards.length);

        for (uint256 i = 0; i < extraRewards.length; i++) {
            IRewardNew.UserRewardInfo memory rewardInfo = extraRewards[i].getUserRewardInfo(_user);

            rewards[i] = UserRewardInfo({
                rewardAddress: address(extraRewards[i]),
                rewardToken: address(extraRewards[i].getRewardToken()),
                rewardAmount: extraRewards[i].calculateReward(_user, userInfoMap[_user].underlyingAmount),
                claimAmount: rewardInfo.rewardAmount,
                lastClaimTime: rewardInfo.lastClaimTime
            });
        }

        return (user.underlyingAmount, rewards);
    }

    /// @notice Get single pool TVL
    function getPoolTvl() public view returns (uint256){
        return totalDeposits;
    }

    /// @notice Get the extra rewards
    function getExtraRewards() public view returns (IRewardNew[] memory){
        return extraRewards;
    }

    /// @notice Calculate the cToken amount
    function cTokenToUnderlying(uint256 _cTokenAmount) public view returns (uint256) {
        uint256 exchangeRate = mendiCToken.exchangeRateStored();
        return (_cTokenAmount * exchangeRate) / 1e18;
    }

    /// @notice Calculate the underlying amount
    function underlyingToCToken(uint256 _underlyingAmount) public view returns (uint256) {
        uint256 exchangeRate = mendiCToken.exchangeRateStored();
        return (_underlyingAmount * 1e18) / exchangeRate;
    }

    receive() external payable {}
}