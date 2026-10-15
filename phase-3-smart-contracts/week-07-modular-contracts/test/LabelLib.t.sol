// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {LabelLib} from "../src/libraries/LabelLib.sol";

/// @dev Internal library functions that take `calldata` need an external entry point
///      to test. This "harness" contract provides one.
contract LabelLibHarness {
    function validate(string calldata label) external pure {
        LabelLib.validate(label);
    }

    function isValid(string memory label) external pure returns (bool) {
        return LabelLib.isValid(label);
    }
}

contract LabelLibTest is Test {
    LabelLibHarness internal lib;

    function setUp() public {
        lib = new LabelLibHarness();
    }

    function test_AcceptsPrintableAscii() public view {
        lib.validate("BSc Computer Science (Hons) ~ 2026!");
        assertTrue(lib.isValid("ok"));
    }

    function test_RevertWhen_Empty() public {
        vm.expectRevert(abi.encodeWithSelector(LabelLib.InvalidLabelLength.selector, 0, 64));
        lib.validate("");
    }

    function test_RevertWhen_TooLong() public {
        string memory long = string(new bytes(65));
        vm.expectRevert(abi.encodeWithSelector(LabelLib.InvalidLabelLength.selector, 65, 64));
        lib.validate(long);
    }

    function test_RevertWhen_NonAscii() public {
        // "é" is 0xC3 0xA9 in UTF-8; the first byte is rejected at position 1.
        vm.expectRevert(
            abi.encodeWithSelector(LabelLib.InvalidLabelCharacter.selector, 1, bytes1(0xc3))
        );
        lib.validate(unicode"cé");
    }

    /// @dev Property: validate() reverts exactly when isValid() returns false.
    function testFuzz_ValidateAgreesWithIsValid(string calldata label) public {
        bool expected = lib.isValid(label);
        if (!expected) vm.expectRevert();
        lib.validate(label);
    }
}
