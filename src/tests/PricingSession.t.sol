// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/test.sol";

import {PricingSession} from "../PricingSession.sol";


contract PricingSessionTest is DSTest {
    PricingSession pricingSession;

    function setUp() public {
        // pricingSession = new PricingSession();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
