"""Local pytest guard for the server; loaded through PYTEST_PLUGINS, see
~/.config/fish/conf.d/machine.fish.

Agents run several test suites at once on a 29 GB box. Suites that use
`-n auto` (one xdist worker per CPU) and size in-test process pools from
os.cpu_count() fan out to hundreds of Python processes, the OOM killer reaps
some of them, and the survivors deadlock waiting on results that never come.
Nothing in those runs has a timeout, so they sit resident for days.

This plugin caps the fan-out and hard-kills a session past its deadline,
dumping every thread's stack first so the deadlock can be found.

Knobs (environment variables):
  PYTEST_LOCALGUARD_CPUS             max xdist workers and reported CPU count (4)
  PYTEST_LOCALGUARD_GIB_PER_WORKER   memory budget per xdist worker (1.5)
  PYTEST_LOCALGUARD_SESSION_TIMEOUT  seconds before the session is killed (3600)
"""

from __future__ import annotations

import faulthandler
import os
import sys
import threading

import pytest

CPU_CAP = int(os.environ.get("PYTEST_LOCALGUARD_CPUS", "4"))
GIB_PER_WORKER = float(os.environ.get("PYTEST_LOCALGUARD_GIB_PER_WORKER", "1.5"))
SESSION_TIMEOUT_S = int(os.environ.get("PYTEST_LOCALGUARD_SESSION_TIMEOUT", "3600"))

_deadline: threading.Timer | None = None


def _mem_available_gib() -> float | None:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) / 2**20
    except OSError:
        pass
    return None


@pytest.hookimpl(tryfirst=True)
def pytest_load_initial_conftests(early_config: pytest.Config) -> None:
    # Runs before any conftest imports application code, so module-level
    # defaults computed from os.cpu_count() see the cap too. The environment
    # variable carries it into interpreters spawned later (xdist workers,
    # ProcessPoolExecutor children) — Python 3.13+ reads it at startup.
    os.environ.setdefault("PYTHON_CPU_COUNT", str(CPU_CAP))
    os.cpu_count = lambda: CPU_CAP
    if hasattr(os, "process_cpu_count"):
        os.process_cpu_count = lambda: CPU_CAP


@pytest.hookimpl(optionalhook=True)
def pytest_xdist_auto_num_workers(config: pytest.Config) -> int:
    # Consulted only when the project's own hook declines (returns None).
    mem = _mem_available_gib()
    if mem is None:
        return CPU_CAP
    return max(1, min(CPU_CAP, int(mem / GIB_PER_WORKER)))


def _kill_session() -> None:
    sys.stderr.write(
        f"\npytest_localguard: session exceeded {SESSION_TIMEOUT_S}s; "
        "dumping all thread stacks and exiting\n"
    )
    sys.stderr.flush()
    faulthandler.dump_traceback(all_threads=True)
    os._exit(70)


def pytest_sessionstart(session: pytest.Session) -> None:
    global _deadline
    _deadline = threading.Timer(SESSION_TIMEOUT_S, _kill_session)
    _deadline.daemon = True
    _deadline.start()


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    if _deadline is not None:
        _deadline.cancel()
