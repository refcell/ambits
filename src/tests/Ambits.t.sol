// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/test.sol";

import {Ambits} from "../Ambits.sol";


contract AmbitsTest is DSTest {
    Ambits ambits;

    function setUp() public {
        ambits = new Ambits(
          0, // lowerBound
          100, // upperBound
          1 // value
        );
    }

    function test_max_ambits() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
