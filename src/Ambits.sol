// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import {Auth} from "solmate/auth/Auth.sol";

/// @title Ambits
/// @notice Adapted Abacus Pricing Sessions
/// @author abigger87
contract Ambits is Auth {
  /// @dev maps each user to their stored principal
  mapping(address => uint) public principalStored;

  /// @dev pricing bounds for the appraisal liquidity range
  struct PricingAmbits {
    uint256 lowerBound;
    uint256 upperBound;
    uint256 value;
  }

  /// @dev Session Ambits
  PricingAmbits public session_ambits;

  /// @dev constructs 
  constructor(
    uint256 lowerBound,
    uint256 upperBound,
    uint256 value
  ) Auth(
    // Owner
    msg.sender,
    // Authority
    msg.sender
  ) {
    session_ambits = PricingAmbits {
      uint256 lowerBound,
      uint256 upperBound,
      uint256 value
    };
  }


}
