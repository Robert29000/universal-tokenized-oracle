"""pytest fixtures: compile the Solidity wrappers (test/mocks/wrappers/) with Foundry and run them inside py-evm (titanoboa).

The bytecode comes from `FOUNDRY_PROFILE=differential forge build` (evm_version = cancun, output in
out-differential/), is deployed into titanoboa's in-process py-evm, and is called with raw ABI-encoded
calldata. Custom-error reverts are surfaced as `SolidityRevert(selector)` so tests can assert them.

Environment variables:
  DIFF_SKIP_BUILD=1          do not run `forge build` (use existing out-differential/ artifacts)
  FORGE=/path/to/forge       forge binary (default: `forge` on PATH, then ~/.foundry/bin/forge)
  HYPOTHESIS_PROFILE=...     `default` (fast), `thorough` (many more examples)
  DIFF_EXHAUSTIVE=1          also run the exhaustive sweeps (every year 2007..9999, every day 1970..2400)
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import boa
import pytest
from eth_abi import decode, encode
from eth_utils import keccak
from hypothesis import HealthCheck, settings

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "out-differential"

sys.path.insert(0, str(HERE.parent))  # ../reference.py

settings.register_profile(
    "default", max_examples=300, deadline=None, suppress_health_check=[HealthCheck.too_slow]
)
settings.register_profile(
    "thorough", max_examples=5000, deadline=None, suppress_health_check=[HealthCheck.too_slow]
)
settings.load_profile(os.environ.get("HYPOTHESIS_PROFILE", "default"))

EXHAUSTIVE = os.environ.get("DIFF_EXHAUSTIVE") == "1"


def selector(signature: str) -> bytes:
    return keccak(text=signature)[:4]


class SolidityRevert(Exception):
    """A call reverted. `data` is the raw revert payload (custom-error selector + args)."""

    def __init__(self, data: bytes):
        super().__init__(f"revert 0x{data.hex()}")
        self.data = data

    @property
    def selector(self) -> bytes:
        return self.data[:4]


@dataclass
class EvmContract:
    address: object

    def call(self, signature: str, arg_types: list[str], args: list, ret_types: list[str]):
        data = selector(signature) + encode(arg_types, args)
        computation = boa.env.execute_code(to_address=self.address, data=data, simulate=True)
        if computation.is_error:
            raise SolidityRevert(bytes(computation.output))
        out = decode(ret_types, bytes(computation.output))
        return out[0] if len(out) == 1 else out


def _forge() -> str:
    exe = os.environ.get("FORGE") or shutil.which("forge") or str(Path.home() / ".foundry/bin/forge")
    if not Path(exe).exists() and shutil.which(exe) is None:
        pytest.exit(f"forge not found ({exe}); set FORGE=/path/to/forge", returncode=2)
    return exe


@pytest.fixture(scope="session", autouse=True)
def _build():
    if os.environ.get("DIFF_SKIP_BUILD") == "1":
        return
    env = dict(os.environ, FOUNDRY_PROFILE="differential")
    subprocess.run([_forge(), "build", "--quiet"], cwd=ROOT, env=env, check=True)


def _deploy(name: str) -> EvmContract:
    artifact = OUT / f"{name}.sol" / f"{name}.json"
    if not artifact.exists():
        pytest.exit(f"missing artifact {artifact}; run `FOUNDRY_PROFILE=differential forge build`", returncode=2)
    bytecode = bytes.fromhex(json.loads(artifact.read_text())["bytecode"]["object"].removeprefix("0x"))
    address, _ = boa.env.deploy_code(bytecode=bytecode)
    return EvmContract(address)


@pytest.fixture(scope="session")
def unix(_build) -> EvmContract:
    return _deploy("UnixTimestampWrapper")


@pytest.fixture(scope="session")
def et(_build) -> EvmContract:
    return _deploy("ETTimestampWrapper")
