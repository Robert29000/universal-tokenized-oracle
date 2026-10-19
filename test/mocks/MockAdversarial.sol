// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Adversarial stand-in for any external dependency (price feed, sequencer feed, pause
///         configurator, provider contract). Every call that does not hit one of the setters below is
///         answered by the fallback with a configurable raw payload, so tests can feed malformed ABI
///         data (wrong type, short data, empty data), raw revert data, or burn all gas.
contract MockRawResponder {
    enum Mode {
        Return,
        Revert,
        BurnGas
    }

    bytes internal payload;
    Mode internal mode;

    function setResponse(Mode _mode, bytes calldata _payload) external {
        mode = _mode;
        payload = _payload;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        if (mode == Mode.BurnGas) {
            // Consume all forwarded gas (out-of-gas, no revert data).
            while (true) {}
        }
        bytes memory p = payload;
        if (mode == Mode.Revert) {
            assembly {
                revert(add(p, 32), mload(p))
            }
        }
        return p;
    }
}

/// @notice Pause configurator whose `isPaused()` tries to write storage. The oracle calls it from a
///         `view` function (STATICCALL), so the write must make the read revert instead of changing
///         state or re-entering the oracle.
contract StateChangingPauseConfigurator {
    uint256 public calls;

    function isPaused() external returns (bool) {
        calls += 1;
        return false;
    }
}
