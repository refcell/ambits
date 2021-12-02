// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

interface IABCTreasury {
    function sendABCToken(address recipient, uint _amount) external;

    function getTokensClaimed() external view returns(uint);

    function updateNftPriced() external;

    function updateProfitGenerated(uint _amount) external;

}