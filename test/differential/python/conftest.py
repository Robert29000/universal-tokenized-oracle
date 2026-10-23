"""pytest fixtures: compile the Solidity wrappers (test/mocks/wrappers/) with Foundry and run them inside py-evm (titanoboa).

The bytecode comes from `FOUNDRY_PROFILE=differential forge build` (evm_version = cancun, output in
out-differential/), is deployed into titanoboa's in-process py-evm, and is called with raw ABI-encoded
calldata. Custom-error reverts are surfaced as `SolidityRevert(selector)` so tests can assert them.

Environment variables:
  DIFF_SKIP_BUILD=1          do not run `forge build` (use existing out-differential/ artifacts)
  FORGE=/path/to/forge       forge binary (default: `forge` on PATH, then ~/.foundry/bin/forge)
  HYPOTHESIS_PROFILE=...     `default` (fast), `thorough` (many more examples)
  DIFF_EXHAUSTIVE=1          also run the exhaustive sweeps (every year 2007..9999, every day 1970..2400,
                             every hour of 2024..2026 with and without holidays, every 10 minutes of
                             2024..2026 for the transition windows)
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


U256 = "uint256"


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

    def transact(self, signature: str, arg_types: list[str], args: list) -> None:
        """State-changing call from the deployer (boa.env.eoa), for example an `onlyOwner` setter."""
        data = selector(signature) + encode(arg_types, args)
        computation = boa.env.execute_code(to_address=self.address, data=data)
        if computation.is_error:
            raise SolidityRevert(bytes(computation.output))


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


def _deploy(name: str, ctor_types: list[str] | None = None, ctor_args: list | None = None) -> EvmContract:
    artifact = OUT / f"{name}.sol" / f"{name}.json"
    if not artifact.exists():
        pytest.exit(f"missing artifact {artifact}; run `FOUNDRY_PROFILE=differential forge build`", returncode=2)
    bytecode = bytes.fromhex(json.loads(artifact.read_text())["bytecode"]["object"].removeprefix("0x"))
    if ctor_types:
        bytecode += encode(ctor_types, ctor_args)
    address, _ = boa.env.deploy_code(bytecode=bytecode)
    return EvmContract(address)


@pytest.fixture(scope="session")
def unix(_build) -> EvmContract:
    return _deploy("UnixTimestampWrapper")


@pytest.fixture(scope="session")
def et(_build) -> EvmContract:
    return _deploy("ETTimestampWrapper")


def deploy_staleness_with_holidays(
    holidays, max_staleness: int, trading_staleness: int, reopen_time_wait: int
) -> EvmContract:
    """A new StalenessCheckerWithHolidaysWrapper (aggregator 0x...01) with each date of `holidays` set by the owner.
    The `_build` fixture must have run (request it, or any contract fixture, in the test)."""
    c = _deploy(
        "StalenessCheckerWithHolidaysWrapper",
        ["address", U256, U256, U256],
        ["0x" + "00" * 19 + "01", max_staleness, trading_staleness, reopen_time_wait],
    )
    for d in sorted(holidays):
        c.transact("setHolidayET(uint256,uint256,uint256,bool)", [U256, U256, U256, "bool"], [d.year, d.month, d.day, True])
    return c


@pytest.fixture(scope="session")
def staleness(_build) -> EvmContract:
    """StalenessCheckerWrapper, for the weekend helpers. They are pure, so the constructor arguments
    (aggregator 0x...01, maxStaleness 1, tradingStaleness 1, reopenTimeWait 0) do not matter."""
    return _deploy(
        "StalenessCheckerWrapper", ["address", U256, U256, U256], ["0x" + "00" * 19 + "01", 1, 1, 0]
    )


def deploy_transition_with_holidays(holidays, default_window: int, own_windows: dict[int, int] | None = None) -> EvmContract:
    """A new TransitionCheckerWithHolidaysWrapper (aggregator 0x...01) with `default_window`, an own window for each
    transition in `own_windows` ({Transition index: window}) and each date of `holidays` set by the owner.
    The `_build` fixture must have run (request it, or any contract fixture, in the test)."""
    c = _deploy("TransitionCheckerWithHolidaysWrapper", ["address", U256], ["0x" + "00" * 19 + "01", default_window])
    for transition, window in (own_windows or {}).items():
        c.transact("setTransitionWindow(uint8,bool,uint256)", ["uint8", "bool", U256], [transition, True, window])
    for d in sorted(holidays):
        c.transact("setHolidayET(uint256,uint256,uint256,bool)", [U256, U256, U256, "bool"], [d.year, d.month, d.day, True])
    return c
