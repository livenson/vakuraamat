#!/usr/bin/env python3
"""Market snapshot for a tile: land value medians per intended purpose, derived from the 2022 taxation values in
sites/<site>/parcels.json, optionally joined with a hand-exported Maa-amet transaction statistics table.

    python3 tools/pipeline/market.py --site kvissentali [--xlsx <maaamet_export.xlsx>] [--root <workspace>]

Writes sites/<site>/market.json: {"attribution", "source", "fetched", "valuation_year", "county", "settlement",
"municipality", "by_purpose": {"ELAMUMAA": {"median_eur_m2", "p25", "p75", "n", "total_area", "total_value"}, ..., "all": {...}},
"transactions": null | {"source", "period", "by_purpose": {<purpose>: {"n", "median_eur_m2"}}}}.
The medians are taxation values (maa korraline hindamine 2022), not sale prices; the ledger uses `transactions`
when a Maa-amet export is present and `by_purpose` otherwise. The Maa-amet statistics environment
(https://www.maaruum.ee/kinnisvara/htraru/) has no API, so the XLSX import is best effort: it looks for a
header row mentioning "mediaan" or "€/m²", a purpose column and a count column.
"""
import argparse, json, os, re, statistics, sys, time, zipfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ATTRIBUTION = "Maakataster (maa maksustamishind 2022): Maa- ja Ruumiamet"
PURPOSE_WORDS = {"elamumaa": "ELAMUMAA", "ärimaa": "ARIMAA", "tootmismaa": "TOOTMISMAA", "maatulundusmaa": "MAATULUNDUSMAA",
                 "transpordimaa": "TRANSPORDIMAA", "üldkasutatav": "ULDKASUTATAV_MAA", "ühiskondlike": "UHISKONDLIKE_EHITISTE_MAA"}


def log(msg):
    print(f"[market] {msg}", flush=True)


def quantile(vals, q):
    vals = sorted(vals)
    if not vals:
        return None
    pos = (len(vals) - 1) * q
    lo, hi = int(pos), min(int(pos) + 1, len(vals) - 1)
    return round(vals[lo] + (vals[hi] - vals[lo]) * (pos - lo), 2)


def stats(units):
    per = [u["land_value_per_m2"] for u in units if u.get("land_value_per_m2")]
    if not per:
        return None
    return {"median_eur_m2": round(statistics.median(per), 2), "p25": quantile(per, 0.25), "p75": quantile(per, 0.75), "n": len(per),
            "total_area": sum(u.get("area") or 0 for u in units), "total_value": sum(u.get("land_value") or 0 for u in units)}


def read_xlsx(path):
    """Rows of the first sheet as lists of strings (stdlib only: shared strings + inline values)."""
    z = zipfile.ZipFile(path)
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", ns):
            shared.append("".join(t.text or "" for t in si.iter("{%s}t" % ns["m"])))
    sheet = next(n for n in sorted(z.namelist()) if n.startswith("xl/worksheets/sheet"))
    rows = []
    for row in ET.fromstring(z.read(sheet)).iter("{%s}row" % ns["m"]):
        cells = []
        for c in row.findall("m:c", ns):
            v = c.find("m:v", ns)
            val = v.text if v is not None else ""
            if c.get("t") == "s" and val.isdigit():
                val = shared[int(val)]
            cells.append(val or "")
        rows.append(cells)
    return rows


def import_transactions(rows, basename):
    """Best-effort mapping of a Maa-amet price statistics export: purpose column, count column, median €/m² column."""
    head_i = next((i for i, r in enumerate(rows) if any(re.search(r"mediaan|€/m", c, re.I) for c in r)), None)
    if head_i is None:
        log(f"{basename}: no header row with 'mediaan' or '€/m²'; transactions skipped")
        return None
    head = [c.lower() for c in rows[head_i]]
    med_i = next((i for i, c in enumerate(head) if "mediaan" in c or "€/m" in c), None)
    cnt_i = next((i for i, c in enumerate(head) if "tehing" in c or "arv" in c), None)
    out, period = {}, None
    for r in rows[:head_i]:
        m = re.search(r"(19|20)\d\d(\s*[-–]\s*(19|20)\d\d)?", " ".join(r))
        if m:
            period = m.group(0)
    for r in rows[head_i + 1:]:
        text = " ".join(r).lower()
        purpose = next((code for word, code in PURPOSE_WORDS.items() if word in text), None)
        if not purpose or med_i is None or med_i >= len(r):
            continue
        try:
            med = float(str(r[med_i]).replace(",", ".").replace(" ", ""))
        except ValueError:
            continue
        n = None
        if cnt_i is not None and cnt_i < len(r):
            try:
                n = int(float(str(r[cnt_i]).replace(",", ".").replace(" ", "")))
            except ValueError:
                n = None
        out[purpose] = {"median_eur_m2": round(med, 2), "n": n}
    if not out:
        log(f"{basename}: header found but no purpose rows recognised; transactions skipped")
        return None
    return {"source": f"Maa-amet tehingute andmebaas, käsitsi eksport {basename}", "period": period, "by_purpose": out}


def derive(site, root=ROOT, xlsx=None):
    site_dir = os.path.join(root, "sites", site)
    d = json.load(open(os.path.join(site_dir, "parcels.json")))
    units = d.get("parcels", [])
    if not any(u.get("land_value") for u in units):
        log(f"sites/{site}/parcels.json has no land_value (re-run make parcels); market.json not written")
        return None
    groups = {}
    for u in units:
        if u.get("land_value") and u.get("area"):
            groups.setdefault(u["purpose"][0] if u.get("purpose") else "SIHTOTSTARBETA_MAA", []).append(u)
    by_purpose = {k: stats(v) for k, v in sorted(groups.items()) if stats(v)}
    by_purpose["all"] = stats([u for v in groups.values() for u in v])
    summary = d.get("summary") or {}
    out = {"attribution": ATTRIBUTION, "source": "derived from maks_hind", "fetched": time.strftime("%Y-%m-%d"),
           "valuation_year": (d.get("valuation") or {}).get("year", 2022), "county": summary.get("county"),
           "settlement": (summary.get("settlements") or [None])[0], "municipality": (summary.get("municipalities") or [None])[0],
           "by_purpose": by_purpose, "transactions": None}
    if xlsx:
        out["transactions"] = import_transactions(read_xlsx(xlsx), os.path.basename(xlsx))
        if out["transactions"]:
            out["source"] = "derived from maks_hind + Maa-amet transaction statistics (xlsx)"
    json.dump(out, open(os.path.join(site_dir, "market.json"), "w"), ensure_ascii=False, indent=1)
    top = {k: v["median_eur_m2"] for k, v in by_purpose.items()}
    log(f"wrote sites/{site}/market.json: median EUR/m² {top}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--xlsx", default=None, help="hand-exported Maa-amet transaction statistics table")
    a = ap.parse_args()
    derive(a.site, a.root, a.xlsx)
    sys.exit(0)
