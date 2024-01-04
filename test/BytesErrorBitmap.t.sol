// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../src/BytesErrorBitmap.sol";

bytes32 constant BIT_ONE_MASK = bytes32(uint(1));

contract BytesErrorBitmapTest is Test {
    BytesErrorBitmap public bitmap;
    Callee public callee;

    Execution public execSuccess =
        Execution(
            address(0),
            0,
            abi.encodeWithSelector(Callee.foo.selector, false)
        );
    Execution public execFail =
        Execution(
            address(0),
            0,
            abi.encodeWithSelector(Callee.foo.selector, true)
        );

    function setUp() public {
        bitmap = new BytesErrorBitmap();
        callee = new Callee();

        execSuccess.target = address(callee);
        execFail.target = address(callee);
    }

    function test_Success() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](1);
        execs[0] = AllowFailedExecution(execSuccess, false, Operation.Call);
        bytes memory result = bitmap.batchExeAllowFail(execs);
        assertEq(
            result,
            hex"00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000"
        );
    }

    function test_Fail() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](1);
        execs[0] = AllowFailedExecution(execFail, true, Operation.Call);
        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"0000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    function test_Revert() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](1);
        execs[0] = AllowFailedExecution(execFail, false, Operation.Call);
        try bitmap.batchExeAllowFail(execs) {
            revert("should revert");
        } catch (bytes memory reason) {
            assertEq(
                reason,
                hex"0000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
            );
        }
    }

    function test_FailFail() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](2);
        execs[0] = AllowFailedExecution(execFail, true, Operation.Call);
        execs[1] = AllowFailedExecution(execFail, true, Operation.Call);
        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"0000000000000000000000000000000000000000000000000000000000000002c00000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e0000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    function test_FailSuccessFail() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](3);
        execs[0] = AllowFailedExecution(execFail, true, Operation.Call);
        execs[1] = AllowFailedExecution(execSuccess, true, Operation.Call);
        execs[2] = AllowFailedExecution(execFail, true, Operation.Call);
        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"0000000000000000000000000000000000000000000000000000000000000003a00000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e0000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    function test_FailSuccessOverflowSuccess() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](257);
        execs[0] = AllowFailedExecution(execFail, true, Operation.Call);
        for (uint i = 1; i < 256; i++) {
            execs[i] = AllowFailedExecution(execSuccess, true, Operation.Call);
        }
        execs[256] = AllowFailedExecution(execSuccess, true, Operation.Call);
        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"00000000000000000000000000000000000000000000000000000000000001018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    function test_FailSuccessOverflowFail() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](257);
        execs[0] = AllowFailedExecution(execFail, true, Operation.Call);
        for (uint i = 1; i < 256; i++) {
            execs[i] = AllowFailedExecution(execSuccess, true, Operation.Call);
        }
        execs[256] = AllowFailedExecution(execFail, true, Operation.Call);
        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"00000000000000000000000000000000000000000000000000000000000001018000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e0000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    function test_FailNested() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](1);
        AllowFailedExecution[] memory _execs = new AllowFailedExecution[](1);
        _execs[0] = AllowFailedExecution(execFail, true, Operation.Call);
        execs[0] = AllowFailedExecution(
            Execution(
                address(bitmap),
                0,
                abi.encodeWithSelector(
                    BytesErrorBitmap._batchExeAllowFail.selector,
                    _execs
                )
            ),
            false,
            Operation.Call
        );
        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"0000000000000000000000000000000000000000000000000000000000000002800000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    function test_FailFailNested() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](1);
        AllowFailedExecution[] memory _execs = new AllowFailedExecution[](2);
        _execs[0] = AllowFailedExecution(execFail, true, Operation.Call);
        _execs[1] = AllowFailedExecution(execFail, true, Operation.Call);
        execs[0] = AllowFailedExecution(
            Execution(
                address(bitmap),
                0,
                abi.encodeWithSelector(
                    BytesErrorBitmap._batchExeAllowFail.selector,
                    _execs
                )
            ),
            false,
            Operation.Call
        );
        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"0000000000000000000000000000000000000000000000000000000000000003c00000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e0000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    function test_SuccessRevertSuccessNested() public {
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](1);
        AllowFailedExecution[] memory execs1 = new AllowFailedExecution[](3);

        execs1[0] = AllowFailedExecution(execSuccess, true, Operation.Call);
        execs1[1] = AllowFailedExecution(execFail, false, Operation.Call);
        execs1[2] = AllowFailedExecution(execFail, false, Operation.Call);

        execs[0] = AllowFailedExecution(
            Execution(
                address(bitmap),
                0,
                abi.encodeWithSelector(
                    BytesErrorBitmap._batchExeAllowFail.selector,
                    execs1
                )
            ),
            true,
            Operation.Call
        );

        bytes memory result = bitmap.batchExeAllowFail(execs);

        assertEq(
            result,
            hex"0000000000000000000000000000000000000000000000000000000000000003600000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
        );
    }

    // function test_BatchesNested() public {
    //     AllowFailedExecution[] memory execs = new AllowFailedExecution[](2);
    //     AllowFailedExecution[] memory execs1 = new AllowFailedExecution[](3);
    //     AllowFailedExecution[] memory execs2 = new AllowFailedExecution[](3);

    //     execs1[0] = AllowFailedExecution(execSuccess, true, Operation.Call);
    //     execs1[1] = AllowFailedExecution(execFail, false, Operation.Call);
    //     execs1[2] = AllowFailedExecution(execFail, false, Operation.Call);

    //     execs2[0] = AllowFailedExecution(execSuccess, false, Operation.Call);
    //     execs2[1] = AllowFailedExecution(execFail, true, Operation.Call);
    //     execs2[2] = AllowFailedExecution(execSuccess, true, Operation.Call);

    //     execs[0] = AllowFailedExecution(
    //         Execution(
    //             address(bitmap),
    //             0,
    //             abi.encodeWithSelector(
    //                 BytesErrorBitmap._batchExeAllowFail.selector,
    //                 execs1
    //             )
    //         ),
    //         true,
    //         Operation.Call
    //     );
    //     execs[1] = AllowFailedExecution(
    //         Execution(
    //             address(bitmap),
    //             0,
    //             abi.encodeWithSelector(
    //                 BytesErrorBitmap._batchExeAllowFail.selector,
    //                 execs2
    //             )
    //         ),
    //         true,
    //         Operation.Call
    //     );

    //     bytes memory result = bitmap.batchExeAllowFail(execs);

    //     assertEq(
    //         result,
    //         hex"0000000000000000000000000000000000000000000000000000000000000006480000000000000000000000000000000000000000000000000000000000000072657665727420726561736f6e0000000000000000000000000000000000000072657665727420726561736f6e00000000000000000000000000000000000000"
    //     );
    // }

    function testFuzz_OneLayer(bool[] calldata shouldFails) public {
        uint len = shouldFails.length;
        uint expectLen = len > 0 ? 2 : 1;
        expectLen += len / 256;
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](len);
        for (uint i; i < len; i++) {
            Execution memory exec = Execution(
                address(callee),
                0,
                abi.encodeWithSelector(Callee.foo.selector, shouldFails[i])
            );
            execs[i] = AllowFailedExecution(exec, true, Operation.Call);
            if (shouldFails[i]) {
                expectLen++;
            }
        }
        bytes memory result = bitmap.batchExeAllowFail(execs);
        // Check counter
        bytes32 counter;
        assembly {
            counter := mload(add(result, 0x20))
        }
        assertEq(uint(counter), len);
        // Check total length
        assertEq(result.length, expectLen * 32);
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

    function testFuzz_TwoLayers(bool[][] memory shouldFails) public {
        uint firstLen = shouldFails.length;
        if (firstLen > 10) firstLen = 10; // Limit
        uint count = firstLen;
        uint failCount;
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](
            firstLen
        );
        for (uint i; i < firstLen; i++) {
            bool[] memory _shouldFails = shouldFails[i];
            uint secondLen = _shouldFails.length;
            if (secondLen > 10) secondLen = 10; // Limit
            if (secondLen == 0) {
                execs[i] = AllowFailedExecution(
                    execSuccess,
                    true,
                    Operation.Call
                );
                continue;
            }
            count += secondLen;
            AllowFailedExecution[] memory _execs = new AllowFailedExecution[](
                secondLen
            );
            for (uint j; j < secondLen; j++) {
                _execs[j] = AllowFailedExecution(
                    Execution(
                        address(callee),
                        0,
                        abi.encodeWithSelector(
                            Callee.foo.selector,
                            _shouldFails[j]
                        )
                    ),
                    true,
                    Operation.Call
                );
                if (_shouldFails[j]) {
                    failCount++;
                }
            }
            execs[i] = AllowFailedExecution(
                Execution(
                    address(bitmap),
                    0,
                    abi.encodeWithSelector(
                        BytesErrorBitmap._batchExeAllowFail.selector,
                        _execs
                    )
                ),
                true,
                Operation.Call
            );
        }

        bytes memory result = bitmap.batchExeAllowFail(execs);

        // Check counter
        assertEq(uint(bytes32(result)), count);

        // Check total length
        uint expectLen = count > 0 ? 2 : 1;
        expectLen += count / 256;
        expectLen += failCount;
        assertEq(result.length, expectLen * 32);
    }

    function checkBitmap(
        AllowFailedExecution[] calldata execs,
        bool[] calldata fails,
        bytes memory bits
    ) public returns (bool reverted, bytes memory remainingBits) {
        uint len = fails.length;
        for (uint i; i < len; i++) {
            bool bit;
            assembly {
                // load bitmap
                bit := mload(add(bits, 0x40))
                // shift bit of interest to leftmost
                bit := shr(sub(255, i), bit)
                // mask bit of interest
                bit := and(
                    0x0000000000000000000000000000000000000000000000000000000000000001,
                    bit
                )
            }
            assertEq(bit, fails[i]);

            if (!bit && execs[i].allowFailed) {
                assembly {
                    // remainingBits :=
                }
            }
        }
    }

    function checkBitmap(
        AllowFailedExecution[][] calldata execs,
        bool[][] calldata fails,
        bytes memory bits
    ) public returns (bool reverted) {
        uint len = fails.length;
        for (uint i; i < len; i++) {
            bool bit;
            assembly {
                // load bitmap
                bit := mload(add(bits, 0x40))
                // shift bit of interest to leftmost
                bit := shr(sub(255, i), bit)
                // mask bit of interest
                bit := and(
                    0x0000000000000000000000000000000000000000000000000000000000000001,
                    bit
                )
            }
            // assertEq(bit, fails[i]);
        }
    }
}
