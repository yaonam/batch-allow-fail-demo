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
                abi.encodeWithSelector(Callee.foo.selector, shouldFails[i])
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

    function testFuzz_TwoLayers(bool[][] memory shouldFails) public {
        uint firstLen = shouldFails.length;
        if (firstLen > 10) firstLen = 10; // Limit
        uint count = firstLen;
        AllowFailedExecution[] memory execs = new AllowFailedExecution[](
            firstLen
        );
        for (uint i; i < firstLen; i++) {
            bool[] memory _shouldFails = shouldFails[i];
            uint secondLen = _shouldFails.length;
            if (secondLen > 10) secondLen = 10; // Limit
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

        assertEq(count % 256, uint(bytes32(result)));
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
