#!/usr/bin/env python3
"""Checks on the pipeline's pure functions, run by `make test` before the Godot scenes.

    python3 tools/pipeline_test.py

Small and dependency-free on purpose: these are the rules a pack is rejected for, so they are worth
holding onto without a test framework or a network.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "pipeline"))
import register_extra  # noqa: E402

# the shape validate_site.py demands of every id in tenants.json "owners"
ALLOWED = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\d{6,}")
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def test_holder_id():
    """A holder's id is opaque, comparable, and never free text.

    The register hands foreign holders whatever their own country calls them, and one of those
    ("900 606 898 R. C. S. Paris") stopped a world being made in v0.4.1: the pack failed validation
    at 77% and the player got nothing.
    """
    keep = ["556333fe-f76c-5e45-8ccf-b394fb5a20fa", "10867775", "900606898"]
    for v in keep:
        check(register_extra.holder_id(v) == v, f"holder_id changed an id it should keep: {v!r}")

    foreign = ["900 606 898 R. C. S. Paris", "HRB 153232", "HRB 242996 B", "2019/179296/07",
               "556185-1428", "2945125-1", "Jaan Tamm"]
    for v in foreign:
        got = register_extra.holder_id(v)
        check(got is not None, f"holder_id dropped a real foreign id: {v!r}")
        check(ALLOWED.fullmatch(str(got)) is not None, f"holder_id({v!r}) = {got!r}, which validate_site rejects")
        check(v.casefold() not in str(got).casefold(), f"holder_id({v!r}) still contains the text")
        check(register_extra.holder_id(v) == got, f"holder_id({v!r}) is not stable between calls")

    # the same holder in two companies has to hash the same, or co-ownership stops linking
    check(register_extra.holder_id("HRB 153232") == register_extra.holder_id("hrb 153232"),
          "holder_id does not fold case, so one holder would look like two")

    # "no identifier" links nothing: hashing it would make every company that wrote it co-owned
    for v in ["", "  ", "-", "--", "puudub", "Puudub", "n/a", "0", None]:
        check(register_extra.holder_id(v) is None, f"holder_id kept a placeholder as an id: {v!r}")


def main():
    test_holder_id()
    if failures:
        print("[pipeline] FAILED:")
        for f in failures:
            print("   ", f)
        return 1
    print("[pipeline] PASSED: holder ids stay opaque, stable and linkable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
