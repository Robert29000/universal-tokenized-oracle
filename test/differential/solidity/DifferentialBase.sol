// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Shared plumbing for the Python differential tests.
/// @dev These tests need `ffi`, which is only enabled in the `differential` profile:
///          FOUNDRY_PROFILE=differential forge test
///      In any other profile every test in a derived contract is skipped.
///      The interpreter defaults to `python3` (the reference script only needs the standard library);
///      override it with DIFF_PYTHON, e.g. DIFF_PYTHON=.venv/bin/python.
abstract contract DifferentialBase is Test {
    string internal constant SCRIPT = "test/differential/solidity/ffi_reference.py";

    string internal python;

    function setUp() public virtual {
        bool enabled = keccak256(bytes(vm.envOr("FOUNDRY_PROFILE", string("")))) == keccak256("differential");
        vm.skip(!enabled);
        python = vm.envOr("DIFF_PYTHON", string("python3"));
    }

    function _ffi(string memory _cmd, uint256 _a) internal returns (bytes memory) {
        string[] memory args = new string[](4);
        args[0] = python;
        args[1] = SCRIPT;
        args[2] = _cmd;
        args[3] = vm.toString(_a);
        return vm.ffi(args);
    }

    function _ffi(string memory _cmd, uint256 _a, uint256 _b) internal returns (bytes memory) {
        string[] memory args = new string[](5);
        args[0] = python;
        args[1] = SCRIPT;
        args[2] = _cmd;
        args[3] = vm.toString(_a);
        args[4] = vm.toString(_b);
        return vm.ffi(args);
    }

    function _ffi(string memory _cmd, uint256 _a, uint256 _b, uint256 _c) internal returns (bytes memory) {
        string[] memory args = new string[](6);
        args[0] = python;
        args[1] = SCRIPT;
        args[2] = _cmd;
        args[3] = vm.toString(_a);
        args[4] = vm.toString(_b);
        args[5] = vm.toString(_c);
        return vm.ffi(args);
    }
}
