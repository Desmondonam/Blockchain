// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DataLocations} from "../src/labs/DataLocations.sol";
import {RequireStrings, CustomErrors} from "../src/labs/ErrorStyles.sol";

contract DataLocationsTest is Test {
    DataLocations internal lab;

    function setUp() public {
        lab = new DataLocations();
    }

    function test_StoragePointerPersists() public {
        lab.updateViaStoragePointer(42);
        (uint256 value,) = lab.item();
        assertEq(value, 42);
    }

    function test_MemoryCopyDoesNotPersist() public view {
        uint256 copyValue = lab.updateViaMemoryCopy(42);
        (uint256 value,) = lab.item();
        assertEq(copyValue, 42, "the copy changed");
        assertEq(value, 1, "storage did not");
    }

    function test_StorageArrayCopiedToMemory() public {
        (uint256 storageLength, uint256 memoryLength) = lab.pushThenCopy(7);
        assertEq(storageLength, 1);
        assertEq(memoryLength, 1);
        assertEq(lab.numbers(0), 7, "storage unaffected by snapshot[0] = 999");
    }

    function test_CalldataCheaperThanMemory() public view {
        uint256[] memory input = new uint256[](50);
        for (uint256 i; i < 50; ++i) {
            input[i] = i;
        }
        // Warm up: the FIRST call to any address pays ~2,500 extra gas for "cold" account
        // access (EIP-2929). Without this line, whichever function runs first looks expensive.
        lab.sumCalldata(new uint256[](0));

        uint256 g0 = gasleft();
        uint256 a = lab.sumCalldata(input);
        uint256 calldataGas = g0 - gasleft();
        g0 = gasleft();
        uint256 b = lab.sumMemory(input);
        uint256 memoryGas = g0 - gasleft();

        assertEq(a, b);
        console.log("calldata gas:", calldataGas, " memory gas:", memoryGas);
        assertLt(calldataGas, memoryGas);
    }
}

contract GasComparisonTest is Test {
    RequireStrings internal withStrings;
    CustomErrors internal withErrors;

    function setUp() public {
        withStrings = new RequireStrings();
        withErrors = new CustomErrors();
    }

    function test_CustomErrorsAreSmallerAndCheaper() public {
        uint256 sizeStrings = address(withStrings).code.length;
        uint256 sizeErrors = address(withErrors).code.length;

        vm.startPrank(makeAddr("stranger"));
        uint256 g0 = gasleft();
        try withStrings.guarded() {} catch {}
        uint256 gasStrings = g0 - gasleft();
        g0 = gasleft();
        try withErrors.guarded() {} catch {}
        uint256 gasErrors = g0 - gasleft();
        vm.stopPrank();

        console.log("bytecode bytes  strings:", sizeStrings, " errors:", sizeErrors);
        console.log("revert gas      strings:", gasStrings, " errors:", gasErrors);
        assertLt(sizeErrors, sizeStrings);
        assertLt(gasErrors, gasStrings);
    }
}
