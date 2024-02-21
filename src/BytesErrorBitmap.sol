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
        if (shouldFail) revert("revert reason");
    }
}

contract BytesErrorBitmap {
    event BitmapError(bytes bitmap);

    modifier onlySelf() {
        require(msg.sender == address(this), "only self");
        _;
    }

    function batchExeAllowFail(
        AllowFailedExecution[] calldata allowFailExecs
    ) external returns (bytes memory result) {
        // result = _batchExeAllowFail(allowFailExecs);
        try this._batchExeAllowFail(allowFailExecs) returns (bytes memory r) {
            result = r;
        } catch (bytes memory reason) {
            assembly {
                revert(add(reason, 0x20), mload(reason))
            }
        }

        emit BitmapError(result);
    }

    /**
     *
     * 0x00 - 0x20  bitmap length
     * 0x20 - ....  bitmap + reasons
     */
    function _batchExeAllowFail(
        AllowFailedExecution[] calldata allowFailExecs
    ) public onlySelf returns (bytes memory) {
        uint256 execsLen = allowFailExecs.length;
        bool shouldRevert;
        bool success;
        bool isBatch;
        bytes
            memory counterBitMap = hex"0000000000000000000000000000000000000000000000000000000000000000";
        for (uint256 i; i < execsLen; ++i) {
            AllowFailedExecution calldata aFE = allowFailExecs[i];
            shouldRevert = !aFE.allowFailed;
            success = false;
            isBatch = false;
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
                isBatch = true;
            }

            assembly {
                // Helper for shifting reasons
                function shiftReasons(_counterBitMap, _counter, skip) {
                    if gt(
                        mload(_counterBitMap),
                        add(skip, mul(div(_counter, 256), 0x20))
                    ) {
                        // Loop and shift each reason back one slot
                        for {
                            let k := mload(_counterBitMap)
                        } gt(k, add(skip, mul(div(_counter, 256), 0x20))) {
                            k := sub(k, 0x20)
                        } {
                            mstore(
                                add(_counterBitMap, k),
                                mload(add(_counterBitMap, sub(k, 0x20)))
                            )
                        }
                    }
                }

                let counterPos := add(counterBitMap, 0x20)
                let counter := mload(counterPos)

                if isBatch {
                    let aCounter := mload(add(appendee, 0x20))
                    let aLen := mload(appendee) // Save in case overridden?

                    // Append bitmap
                    for {
                        let j := 0x40 // Skip over len + counter
                    } lt(j, add(0x60, mul(div(counter, 256), 0x20))) {
                        j := add(j, 0x20)
                    } {
                        let nextSlot := add(counterBitMap, 0x40) // Skip len and counter
                        if gt(mod(counter, 256), 0) {
                            nextSlot := add(nextSlot, 0x20) // Skip last slot
                        }
                        nextSlot := add(nextSlot, mul(div(counter, 256), 0x20))
                        switch mod(counter, 256)
                        case 0 {
                            // Add entire chunk
                            // Write slot
                            mstore(nextSlot, mload(add(appendee, j)))
                            // Increment counterBitMap length
                            mstore(
                                counterBitMap,
                                add(mload(counterBitMap), 0x20)
                            )
                            // Shift reasons
                            shiftReasons(counterBitMap, counter, 0x40)
                        }
                        default {
                            // Mask and add first part to last slot
                            // Create mask
                            let mask := shr(counter, mload(add(appendee, j)))
                            // Mask last slot
                            mstore(
                                sub(nextSlot, 0x20),
                                or(mload(sub(nextSlot, 0x20)), mask)
                            )

                            // Mask and add remaining part to new slot
                            // Create mask
                            mask := shl(
                                sub(256, counter),
                                mload(add(appendee, j))
                            )
                            if gt(mask, 0) {
                                // Shift reasons
                                shiftReasons(counterBitMap, counter, 0x40)
                                // Go to new slot
                                let newPos := add(nextSlot, 0x20)
                                // Write new slot
                                mstore(nextSlot, mask)
                            }
                        }
                        // Update counter
                        counter := add(counter, aCounter)
                        mstore(counterPos, counter)
                    }

                    // Append reasons
                    for {
                        let j := 0x60 // Skip over len + counter + bitmap 1st slot
                        j := add(j, mul(div(aCounter, 256), 0x20)) // Skip over rest bitmap
                    } lt(j, add(aLen, 0x20)) {
                        j := add(j, 0x20)
                    } {
                        // Increment counterBitMap length
                        mstore(counterBitMap, add(mload(counterBitMap), 0x20))
                        // Write slot
                        mstore(
                            add(mload(counterBitMap), counterBitMap),
                            mload(add(appendee, j))
                        )
                    }
                }

                // Add this tx's bit to bitmap
                switch success
                case true {
                    // Add 0 to bitmap
                    // Check if need allocate memory
                    if eq(mod(counter, 256), 0) {
                        // Increment 0x40 memory pointer
                        mstore(0x40, add(mload(0x40), 0x20))
                        // Increment bitmap length
                        mstore(counterBitMap, add(mload(counterBitMap), 0x20))
                        // Shift reasons
                        shiftReasons(counterBitMap, counter, 0x40)
                        // Clear slot?
                        mstore(
                            add(
                                counterBitMap,
                                add(0x40, mul(div(counter, 256), 0x20))
                            ),
                            0x0000000000000000000000000000000000000000000000000000000000000000
                        )
                    }
                }
                default {
                    // Add 1 to bitmap
                    let nextPos := add(counterBitMap, 0x40) // Skip len and counter

                    switch mod(counter, 256)
                    case 0 {
                        // Increment 0x40 memory pointer
                        // mstore(0x40, add(mload(0x40), 0x20))
                        // Increment counterBitMap length
                        mstore(counterBitMap, add(mload(counterBitMap), 0x20))

                        // Shift reasons
                        shiftReasons(counterBitMap, counter, 0x20)

                        // Write 1 to leftmost bit
                        mstore(nextPos, shl(255, 1))
                    }
                    default {
                        // Create mask
                        let mask := shl(sub(255, counter), 1)
                        // Mask using OR
                        mstore(nextPos, or(mload(nextPos), mask))
                    }

                    if eq(isBatch, false) {
                        // Append reason, should be next slot
                        // Will overwrite appendee, so no need to allocate memory
                        // Get length
                        let len := mload(counterBitMap)
                        // Go to empty byte
                        let newPos := add(add(counterBitMap, len), 0x20)
                        // Write slot
                        mstore(newPos, mload(add(appendee, 0x64)))
                        // Increment counterBitMap length
                        mstore(counterBitMap, add(len, 0x20))
                    }
                }

                // Increment counter
                mstore(counterPos, add(counter, 1))

                if shouldRevert {
                    revert(add(counterBitMap, 0x20), mload(counterBitMap))
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
