// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice MendiCToken interface
interface IMendiCToken {
    function approve(
        address spender,
        uint256 amount
    ) external returns (bool);

    function mint(uint mintAmount) external returns (uint);

    function redeem(uint redeemTokens) external returns (uint);

    function redeemUnderlying(
        uint redeemAmount
    ) external returns (uint);

    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

}
