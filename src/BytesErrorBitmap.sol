// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

enum Operation {
    Call,
    DelegateCall
}
struct Execution {
    address target;
    uint256 value;
    bytes callData;
}

struct AllowFailedExecution {
    Execution execution;
    bool allowFailed;
    Operation operation;
}

contract Callee {
    function foo(bool shouldFail) external pure {
        if (shouldFail) revert();
    }
}

contract BytesErrorBitmap {
    event BitmapError(bytes bitmap);

    function batchExeAllowFail(
        AllowFailedExecution[] calldata allowFailExecs
    ) external returns (bytes memory result) {
        result = _batchExeAllowFail(allowFailExecs);

        emit BitmapError(result);
    }

    /**
     *
     * 0x00 - 0x20  counter
     * 0x20 - ....  bitmap
     */
    function _batchExeAllowFail(
        AllowFailedExecution[] calldata allowFailExecs
    ) public returns (bytes memory) {
        uint execsLen = allowFailExecs.length;
        bool shouldRevert;
        bool success;
        bytes
            memory counterBitMap = hex"0000000000000000000000000000000000000000000000000000000000000000";
        for (uint i; i < execsLen; ++i) {
            AllowFailedExecution calldata aFE = allowFailExecs[i];
            shouldRevert = !aFE.allowFailed;
            success = false;
            bytes memory appendee;
            try
                this.exe(
                    aFE.execution.target,
                    aFE.execution.value,
                    aFE.execution.callData,
                    aFE.operation
                )
            returns (bytes memory result) {
                shouldRevert = false;
                success = true;
                assembly {
                    appendee := add(result, 0x40) // Skip abi encoding prepends
                }
            } catch (bytes memory reason) {
                appendee = reason;
            }

            // If batch, append bits to bitmap
            if (
                aFE.execution.target == address(this) &&
                bytes4(aFE.execution.callData) ==
                this._batchExeAllowFail.selector
            ) {
                assembly {
                    let counterPos := add(counterBitMap, 0x20)
                    let counter := mload(counterPos)

                    let aLen := add(mload(appendee), 0x20)

                    for {
                        let j := 0x40 // Need to skip over counter
                    } lt(j, aLen) {
                        j := add(j, 0x20)
                    } {
                        // Get length
                        let len := mload(counterBitMap)

                        switch counter
                        case 0 {
                            // Add entire chunk
                            // Go to empty byte
                            let newPos := add(counterPos, len)
                            // Write slot
                            mstore(newPos, mload(add(appendee, j)))
                            // Increment counterBitMap length
                            mstore(counterBitMap, add(len, 0x20))
                        }
                        default {
                            // Mask and add first part to last slot
                            // Go to last slot
                            let lastPos := sub(add(counterBitMap, len), 0x00)
                            // Create mask
                            let mask := shr(counter, mload(add(appendee, j)))
                            // Mask last slot
                            mstore(lastPos, or(mload(lastPos), mask))

                            // Mask and add remaining part to new slot
                            // Go to new slot
                            let newPos := add(counterPos, len)
                            // Create mask
                            mask := shl(
                                sub(256, counter),
                                mload(add(appendee, j))
                            )
                            // Write new slot
                            mstore(newPos, mask)
                        }

                        // Update counter
                        counter := add(counter, mload(add(appendee, 0x20)))
                        if gt(counter, 255) {
                            counter := sub(counter, 256)
                            // Increment counterBitMap length
                            mstore(counterBitMap, add(len, 0x20))
                        }
                        mstore(counterPos, counter)
                    }
                }
            }

            // Add this tx's bit to bitmap
            assembly {
                let counterPos := add(counterBitMap, 0x20)
                let counter := mload(counterPos)

                switch success
                case true {
                    // Add 0 to bitmap
                    // Check if need allocate memory
                    if eq(counter, 0) {
                        // Increment 0x40 memory pointer
                        mstore(0x40, add(mload(0x40), 0x20))
                        // Increment bitmap length
                        mstore(counterBitMap, add(mload(counterBitMap), 0x20))
                        // Clear slot?
                        mstore(
                            add(counterBitMap, mload(counterBitMap)),
                            0x0000000000000000000000000000000000000000000000000000000000000000
                        )
                    }

                    // Increment counter
                    switch counter
                    case 255 {
                        mstore(counterPos, 0)
                    }
                    default {
                        mstore(counterPos, add(counter, 1))
                    }
                }
                default {
                    // Add 1 to bitmap
                    switch counter
                    case 0 {
                        // Increment 0x40 memory pointer
                        mstore(0x40, add(mload(0x40), 0x20))

                        // Get length
                        let len := mload(counterBitMap)
                        // Go to empty byte
                        let newPos := add(counterPos, len)
                        // Write 1 to leftmost bit
                        mstore(newPos, shl(255, 1))
                        // Increment counterBitMap length
                        mstore(counterBitMap, add(len, 0x20))

                        // Set counter to 1
                        mstore(counterPos, 0x01)
                    }
                    default {
                        // Get length
                        let len := mload(counterBitMap)
                        // Go to last slot
                        let lastPos := add(counterBitMap, len)
                        // Create mask
                        let mask := shl(sub(255, counter), 1)
                        // Mask using OR
                        mstore(lastPos, or(mload(lastPos), mask))

                        // Update counter
                        switch counter
                        case 255 {
                            mstore(counterPos, 0)
                        }
                        default {
                            mstore(counterPos, add(counter, 1))
                        }
                    }

                    if shouldRevert {
                        revert(add(counterBitMap, 0x20), mload(counterBitMap))
                    }
                }
            }
        }

        return counterBitMap;
    }

    function exe(
        address to,
        uint256 value,
        bytes memory data,
        Operation
    ) external returns (bytes memory result) {
        bool success;
        (success, result) = payable(to).call{value: value}(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
