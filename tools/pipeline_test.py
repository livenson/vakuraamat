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


def test_health_blank_is_not_zero():
    """A blank in the Tax Board's file is an amount it does not publish, not a zero.

    Tartu Lasteaed Rõõmumaa, a city kindergarten with 58 staff, has both tax columns empty every
    quarter (the city pays its taxes) and was painted "distressed" on the map's company-health layer.
    """
    def q(taxes, labour, staff):
        return {"year": 2025, "q": 1, "taxes": taxes, "labour": labour, "turnover": None, "employees": staff}
    h = register_extra.health_of
    check(h("R", [q(None, None, 58)] * 4, False) == "sound", "blank tax columns with staff read as distressed")
    check(h("R", [q(0, 0, 3)] * 4, False) == "distressed", "a year of published zero taxes with staff is no longer distressed")
    check(h("R", [q(0, 900, 3)] * 4, False) == "sound", "an employer paying only payroll taxes reads as distressed")
    check(h("L", [], False) == "distressed", "a company in liquidation is not distressed")
    w = register_extra.health_why
    check(w("R", [q(None, None, 58)] * 4, True) == {"rule": "report"}, "an overdue report does not say so")
    def t(year, turnover):
        return {"year": year, "q": 1, "taxes": 100, "labour": 100, "turnover": turnover, "employees": 1}
    fall = [t(2024, 30000)] * 4 + [t(2025, 5000)] * 4
    check(h("R", fall, False) == "watch" and w("R", fall, False) == {"rule": "turnover", "from": [2024, 120000], "to": [2025, 20000]},
          "a turnover drop does not carry its two years")
    check(w("R", [t(2025, 100)] * 4, False) is None, "a sound company carries a reason")


class _Everything:
    """A laser-sheet index holding every sheet (the real one is a 5 MB download)."""
    def __contains__(self, name):
        return True


def _tile(cx, cy):
    return cx - 512, cy - 512, cx + 512, cy + 512


def test_lv_sheets():
    """A new Latvian world is centred on its laser sheet and downloads that one sheet: the four it
    only grazes are filled, not fetched (fetch_tile_lv.place_center, select_sheets). Needs the
    pipeline's wheels (numpy, pyproj); without them the check says it was skipped."""
    try:
        import fetch_tile_lv
        import pyproj  # noqa: F401 - fetch_tile_lv's transforms
    except ImportError as e:
        return f"laser-sheet checks skipped ({e.name} missing)"
    import random
    every = _Everything()
    rng = random.Random(7)
    for _ in range(150):
        c = fetch_tile_lv.place_center(rng.uniform(320000, 740000), rng.uniform(6190000, 6420000), every)
        check(fetch_tile_lv.place_center(*c, every) == c, f"place_center moves its own centre {c}")
        keep = fetch_tile_lv.select_sheets(_tile(*c), every)[0]
        check(len(keep) == 1, f"a world centred at {c} keeps {keep}")
        # 12 m of overhang plus 20 stays under SKIP_M; 100 m does not
        check(len(fetch_tile_lv.select_sheets(_tile(c[0] + 20, c[1] - 20), every)[0]) == 1, f"20 m off {c} needs more than one sheet")
        check(len(fetch_tile_lv.select_sheets(_tile(c[0] + 100, c[1]), every)[0]) > 1, f"100 m off {c} still keeps one sheet")
        check(len(fetch_tile_lv.select_sheets(_tile(c[0] + 1024, c[1]), every)[0]) <= 2, f"the neighbour east of {c} needs more than two")
    # a tile whose wide sheet is not published (the coast) keeps the narrow ones rather than nothing
    c = fetch_tile_lv.place_center(560000, 6300000, every)
    keep, skip, _ = fetch_tile_lv.select_sheets(_tile(*c), every)
    keep2, skip2, missing2 = fetch_tile_lv.select_sheets(_tile(*c), set(skip))
    check(sorted(keep2) == sorted(skip) and not skip2 and missing2 == keep, f"coast fallback: kept {keep2}, skipped {skip2}")
    # the skipped strips are the tile's edges, 12 m a side, and never its middle
    mask = fetch_tile_lv.skipped_mask(_tile(*c), 1024, skip)
    check(0.03 < mask.mean() < 0.07 and not mask[512, 512] and mask[0, 512] and mask[512, 0], f"skipped strips cover {mask.mean():.1%}")
    return "a Latvian world downloads one laser sheet"


def main():
    test_holder_id()
    test_health_blank_is_not_zero()
    sheets = test_lv_sheets()
    if failures:
        print("[pipeline] FAILED:")
        for f in failures:
            print("   ", f)
        return 1
    print(f"[pipeline] PASSED: holder ids stay opaque, stable and linkable; a blank tax column is not a zero; {sheets}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
