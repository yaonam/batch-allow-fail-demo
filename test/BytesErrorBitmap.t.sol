// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../src/BytesErrorBitmap.sol";

bytes32 constant BIT_ONE_MASK = bytes32(uint(1));

contract BytesErrorBitmapTest is Test {
    BytesErrorBitmap public bitmap;
    Callee public callee;

    function setUp() public {
        bitmap = new BytesErrorBitmap();
        callee = new Callee();
    }

    function testFuzz_OneLayer(bool[] calldata shouldFails) public {
        uint len = shouldFails.length;
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](len);
        for (uint i; i < len; i++) {
            Execution memory exec = Execution(
                address(callee),
                0,
                abi.encodeWithSelector(
                    Callee.ShouldFail.selector,
                    shouldFails[i]
                )
            );
            execs[i] = AllowFailedExecution(exec, true, Operation.Call);
        }
        bytes memory result = bitmap.batchExeAllowFail(execs);
        assertEq(len, uint(bytes32(result)));
        for (uint i; i < len; i++) {
            bool res;
            assembly {
                // load bitmap
                res := mload(add(result, 0x40))
                // shift bit of interest to leftmost
                res := shr(sub(255, i), res)
                // mask bit of interest
                res := and(
                    0x0000000000000000000000000000000000000000000000000000000000000001,
                    res
                )
            }
            assertEq(res, shouldFails[i]);
        }
    }

    function generateCounterBitmap(
        bool[] calldata fails
    ) public returns (bytes memory result) {}

    // function test_Increment() public {
    //     counter.increment();
    //     assertEq(counter.number(), 1);
    // }

    // function testFuzz_SetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
