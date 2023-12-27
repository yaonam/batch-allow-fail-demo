// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../src/BytesErrorBitmap.sol";

contract BytesErrorBitmapTest is Test {
    BytesErrorBitmap public bitmap;
    Callee public callee;

    function setUp() public {
        bitmap = new BytesErrorBitmap();
        callee = new Callee();
    }

    function testFuzz_OneLayer(bool[] calldata oneFails) public {
        console2.log(oneFails.length);
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](
            oneFails.length
        );
        for (uint i; i < oneFails.length; i++) {
            Execution memory exec = Execution(
                address(callee),
                0,
                abi.encodeWithSelector(Callee.ShouldFail.selector, oneFails[i])
            );
            execs[i] = AllowFailedExecution(exec, true, Operation.Call);
        }
        bitmap.batchExeAllowFail(execs);
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
