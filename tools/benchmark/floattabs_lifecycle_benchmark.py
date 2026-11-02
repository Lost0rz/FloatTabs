#!/usr/bin/env python3
"""Retired Stage 5E Hot/Warm/Cold lifecycle benchmark entry point.

Phase 7 replaced the current product lifecycle with Automatic / Keep Loaded.
This historical command must not be used as current acceptance evidence.
Use `floattabs_phase7_acceptance.py` instead. Historical Stage 5E code remains
available in Git history for incident archaeology and regression reference.
"""

from __future__ import annotations

import sys


def main() -> int:
    print(
        "RETIRED: the Hot/Warm/Cold Stage 5E lifecycle benchmark is no longer a "
        "valid FloatTabs acceptance path.\n"
        "Use: python3 tools/benchmark/floattabs_phase7_acceptance.py --help",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
