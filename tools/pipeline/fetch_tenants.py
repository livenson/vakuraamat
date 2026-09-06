#!/usr/bin/env python3
"""Real tenants for a tile: companies from the e-Business Register open data (daily basic-data CSV, CC BY 4.0)
matched to the tile's cadastral units and buildings by address.

    python3 tools/pipeline/fetch_tenants.py --site kvissentali [--stats] [--refresh] [--max-age-days 7]
                                            [--keep-unmatched auto|yes|no] [--include-fie] [--root <workspace>]

Writes sites/<site>/tenants.json: {"attribution", "source", "sources", "fetched", "register_date", "ehak", "stats", "tenants": [
  {registry_code, name, legal_form, status, status_text, active, since, address, ehak, tunnus|null, building_id|null,
   match: exact|street|none, via: ads|address|building|farm|null, link,
   emtak {code, text, nace, section}|null, sector (farm|industry|construction|trade|transport|hospitality|media|finance|
   property|services|public|culture)|null, capital, web, employees, turnover (last four quarters, EUR), taxes,
   employees_hist [[year, n]], quarters [[year, q, turnover, employees]], board_size, shareholders, owner_managed,
   owners [hashed ids], deleted, report_overdue, health: sound|watch|distressed}]}  (register_extra.py: the general
   data, the persons and shareholders files as structure only, the Tax Board's quarterly figures).
Rows are filtered by the settlement codes (EHAK) of the tile's parcels, then matched: the company's ADS address id
against the Building Register ids of the tile's buildings, then a normalised "street + number" key against the
parcel and building addresses, then farm names. `street` rows share a street with the tile but their number is
not in it (kept: the neighbourhood's businesses); `none` rows are kept only for village-sized tiles.
Legal persons only: sole proprietors (FIE) carry a person's name and are skipped unless --include-fie.
Not stored: VAT numbers, postcodes, ADS ids. The ledger shows active companies as tenants; inactive ones
(bankrupt, in liquidation) stay in the file as empty premises.
"""
import argparse, csv, io, json, os, re, sys, time, unicodedata, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_buildings import point_in_poly  # noqa: E402
import register_extra  # noqa: E402

CSV_ZIP = "https://avaandmed.ariregister.rik.ee/sites/default/files/avaandmed/ettevotja_rekvisiidid__lihtandmed.csv.zip"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Äriregistri avaandmed, Registrite ja Infosüsteemide Keskus (CC BY 4.0)"
EMTA_ATTRIBUTION = "Tasutud maksud, käive ja töötajate arv: Maksu- ja Tolliamet (avaandmed)"
LINK = "https://ariregister.rik.ee/est/company/{code}"
STATUS_TEXT = {"R": "registered", "N": "bankrupt", "L": "in liquidation", "K": "deleted"}
STREET_TYPES = {"tänav", "tn", "tee", "puiestee", "pst", "maantee", "mnt", "põik", "allee", "väljak", "plats", "tänava"}
_NUM = re.compile(r"^(?P<stem>.+?)\s+(?P<num>\d+)(?P<sub>[a-zõäöüšž]?)(?:/\d+\w*)?(?:-\d+\w*)?$")
_SUB = re.compile(r"^(\d+)([a-zõäöüšž]?)$")


def log(msg):
    print(f"[fetch_tenants] {msg}", flush=True)


def normalise(addr):
    """'Madruse tn 22-11' -> ('madruse', '22', ''); 'Kvissentali tee 9b' -> ('kvissentali', '9', 'b');
    'Pikk tänav 4' == 'Pikk tn 4' -> ('pikk', '4', ''); 'Raua' -> ('raua', '', '')."""
    s = unicodedata.normalize("NFC", addr or "").lower().replace(" ", " ")
    s = re.sub(r"\s+", " ", re.sub(r"[.,]", " ", s)).strip()
    m = _NUM.match(s)
    stem, num, sub = (m.group("stem"), m.group("num"), m.group("sub")) if m else (s, "", "")
    words = stem.split(" ")
    if len(words) > 1 and words[-1] in STREET_TYPES:
        words = words[:-1]
    return " ".join(words), num, sub


def address_keys(addr):
    """Every alternate of a cadastral address: 'Klaose tn 16 // Meruski tn 14 // 16' -> three keys
    (a bare number continues the previous street)."""
    keys, last = [], None
    for part in (p.strip() for p in (addr or "").split("//") if p.strip()):
        stem, num, sub = normalise(part)
        if not num and last:
            m = _SUB.match(stem)
            if m:
                stem, num, sub = last, m.group(1), m.group(2)
        keys.append((stem, num, sub))
        last = stem
    return keys


def download_register(cache_dir, max_age_days=7, refresh=False):
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, os.path.basename(CSV_ZIP))
    meta_path = path + ".meta.json"
    if os.path.exists(path) and os.path.exists(meta_path) and not refresh:
        meta = json.load(open(meta_path))
        age = (time.time() - time.mktime(time.strptime(meta["downloaded"], "%Y-%m-%d"))) / 86400
        if age < max_age_days:
            return path, meta["downloaded"]
    log(f"downloading {CSV_ZIP}")
    r = urllib.request.urlopen(urllib.request.Request(CSV_ZIP, headers=UA), timeout=600)
    with open(path + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(path + ".part", path)
    today = time.strftime("%Y-%m-%d")
    json.dump({"downloaded": today, "size": os.path.getsize(path), "last_modified": r.headers.get("Last-Modified")}, open(meta_path, "w"))
    return path, today


def iter_rows(zip_path):
    z = zipfile.ZipFile(zip_path)
    name = next(n for n in z.namelist() if n.endswith(".csv"))
    with z.open(name) as raw:
        rd = csv.reader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline=""), delimiter=";")
        head = next(rd)
        for row in rd:
            if len(row) >= len(head):
                yield dict(zip(head, row))


def company_address(row):
    a = (row.get("asukoht_ettevotja_aadressis") or "").strip()
    if a:
        return a
    full = row.get("ads_normaliseeritud_taisaadress") or ""
    return full.split(",")[-1].strip() if "," in full else ""


def build_index(parcels, buildings):
    idx = {"by_key": {}, "by_stem_num": {}, "bkey": {}, "by_adr_id": {}, "streets": set(), "farms": {}, "parcel_of_building": {}}
    for u in parcels:
        for k in address_keys(u.get("address")):
            if k[1]:
                idx["by_key"].setdefault(k, []).append(u["tunnus"])
                idx["by_stem_num"].setdefault(k[:2], []).append(u["tunnus"])
                idx["streets"].add(k[0])
            elif k[0]:
                idx["farms"].setdefault(k[0], []).append(u["tunnus"])
    polys = [(u["tunnus"], u["polygon"]) for u in parcels if u.get("polygon")]
    for b in buildings:
        bid = b.get("id")
        ky = (b.get("cadastral") or [None])[0]
        if not ky:
            ky = next((t for t, poly in polys if point_in_poly(b["x"], b["z"], poly)), None)
        if ky:
            idx["parcel_of_building"][bid] = ky
        for a in set([b.get("address")] + list(b.get("addresses") or [])):
            for k in address_keys(a):
                if k[1]:
                    idx["bkey"].setdefault(k, []).append(b)
                    idx["streets"].add(k[0])
        ads = b.get("ads") or {}
        for key in ("adr_id", "aadr_id"):
            if ads.get(key):
                idx["by_adr_id"].setdefault(str(ads[key]), []).append(b)
    return idx


def best_building(bs):
    return max(bs, key=lambda b: (b.get("kind") != "outbuilding", b.get("w", 0) * b.get("d", 0)))


def match(row, idx):
    adr = (row.get("ads_adr_id") or "").strip()
    if adr and adr in idx["by_adr_id"]:
        b = best_building(idx["by_adr_id"][adr])
        return idx["parcel_of_building"].get(b.get("id")), b.get("id"), "exact", "ads"
    stem, num, sub = normalise(company_address(row))
    if not stem:
        return None, None, "none", None
    if num:
        k = (stem, num, sub)
        if k in idx["by_key"]:
            return idx["by_key"][k][0], None, "exact", "address"
        if not sub and len(idx["by_stem_num"].get((stem, num), [])) == 1:
            return idx["by_stem_num"][(stem, num)][0], None, "exact", "address"
        if k in idx["bkey"]:
            b = best_building(idx["bkey"][k])
            return idx["parcel_of_building"].get(b.get("id")), b.get("id"), "exact", "building"
        if stem in idx["streets"]:
            return None, None, "street", None
        return None, None, "none", None
    if stem in idx["farms"]:
        return idx["farms"][stem][0], None, "exact", "farm"
    return None, None, "none", None


def iso_date(d):
    m = re.match(r"(\d\d)\.(\d\d)\.(\d{4})", d or "")
    return f"{m.group(3)}-{m.group(2)}-{m.group(1)}" if m else (d or None)


def fetch(site, root=ROOT, stats=False, refresh=False, max_age_days=7, keep_unmatched="auto", include_fie=False, enrich=True):
    site_dir = os.path.join(root, "sites", site)
    pd = json.load(open(os.path.join(site_dir, "parcels.json")))
    parcels = pd.get("parcels", [])
    ehak = set((pd.get("summary") or {}).get("ehak") or [u["ehak"] for u in parcels if u.get("ehak")])
    if not ehak:
        log(f"sites/{site}/parcels.json has no EHAK codes (re-run make parcels); tenants.json not written")
        return []
    bpath = os.path.join(site_dir, "buildings.json")
    buildings = json.load(open(bpath)).get("buildings", []) if os.path.exists(bpath) else []
    idx = build_index(parcels, buildings)
    import paths
    zip_path, reg_date = download_register(paths.raw("ariregister"), max_age_days, refresh)
    t0 = time.time()
    st = {"scanned": 0, "in_ehak": 0, "fie_skipped": 0, "kept": 0, "exact": 0, "exact_ads": 0, "exact_address": 0, "exact_building": 0,
          "exact_farm": 0, "street": 0, "none": 0, "by_status": {}}
    candidates, unmatched = [], {}
    for row in iter_rows(zip_path):
        st["scanned"] += 1
        if (row.get("asukoha_ehak_kood") or "") not in ehak:
            continue
        st["in_ehak"] += 1
        if (row.get("ettevotja_oiguslik_vorm") or "").startswith("Füüsilisest isikust") and not include_fie:
            st["fie_skipped"] += 1
            continue
        tunnus, bid, m, via = match(row, idx)
        if m == "exact" and bid is not None and tunnus is None:
            tunnus = None   # building known, parcel unknown: still exact on the building
        if m == "none":
            k = normalise(company_address(row))
            if k[0] in idx["streets"]:
                unmatched[k[:2]] = unmatched.get(k[:2], 0) + 1
        status = (row.get("ettevotja_staatus") or "").strip()
        candidates.append({"registry_code": row.get("ariregistri_kood"), "name": row.get("nimi"), "legal_form": row.get("ettevotja_oiguslik_vorm"),
                           "status": status, "status_text": STATUS_TEXT.get(status, row.get("ettevotja_staatus_tekstina")), "active": status == "R",
                           "since": iso_date(row.get("ettevotja_esmakande_kpv")), "address": company_address(row), "ehak": row.get("asukoha_ehak_kood"),
                           "tunnus": tunnus, "building_id": bid, "match": m, "via": via, "link": LINK.format(code=row.get("ariregistri_kood"))})
    keep_none = keep_unmatched == "yes" or (keep_unmatched == "auto" and st["in_ehak"] <= 200)
    out = [c for c in candidates if c["match"] != "none" or keep_none]
    rank = {"exact": 0, "street": 1, "none": 2}
    out.sort(key=lambda c: (rank[c["match"]], c["name"] or ""))
    for c in out:
        st["kept"] += 1
        st[c["match"]] += 1
        if c["match"] == "exact":
            st["exact_" + c["via"]] += 1
        st["by_status"][c["status"]] = st["by_status"].get(c["status"], 0) + 1
    # the register's general data, its board and shareholder structure and the Tax Board's quarters
    dates = {}
    if enrich:
        try:
            dates = register_extra.enrich(out, root, max_age_days, refresh)
        except Exception as e:  # noqa: BLE001 - the basic file alone still makes a playable pack
            log(f"enrichment unavailable ({e})")
    sectors = {}
    for c in out:
        if c.get("sector"):
            sectors[c["sector"]] = sectors.get(c["sector"], 0) + 1
    st["sectors"] = sectors
    st["with_emtak"] = sum(1 for c in out if c.get("emtak"))
    st["with_tax"] = sum(1 for c in out if c.get("quarters"))
    st["elapsed_s"] = round(time.time() - t0, 1)
    json.dump({"attribution": ATTRIBUTION + ("; " + EMTA_ATTRIBUTION if dates else ""), "source": CSV_ZIP, "sources": dates,
               "fetched": time.strftime("%Y-%m-%d"), "register_date": reg_date, "ehak": sorted(ehak),
               "stats": st, "tenants": out}, open(os.path.join(site_dir, "tenants.json"), "w"), ensure_ascii=False, indent=0)
    log(f"wrote sites/{site}/tenants.json: {st['kept']} companies ({st['exact']} exact: {st['exact_ads']} ads, {st['exact_address']} address, "
        f"{st['exact_building']} building, {st['exact_farm']} farm; {st['street']} street; {st['none']} none) from {st['in_ehak']} in EHAK {sorted(ehak)}, "
        f"{st['scanned']} scanned in {st['elapsed_s']} s")
    if stats:
        log(f"status: {st['by_status']}  sole proprietors skipped: {st['fie_skipped']}")
        log(f"sectors: {dict(sorted(sectors.items(), key=lambda kv: -kv[1]))}  with EMTAK: {st['with_emtak']}  with tax quarters: {st['with_tax']}")
        streets_hit = {normalise(c['address'])[0] for c in out if c['match'] == 'exact'}
        log(f"streets in tile: {len(idx['streets'])}, streets with an exact match: {len(streets_hit)}")
        top = sorted(unmatched.items(), key=lambda kv: -kv[1])[:15]
        log("unmatched on tile streets (stem, number: companies): " + ", ".join(f"{k[0]} {k[1]}: {n}" for k, n in top))
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--refresh", action="store_true", help="re-download the register file even if the cache is fresh")
    ap.add_argument("--max-age-days", type=int, default=7)
    ap.add_argument("--keep-unmatched", choices=["auto", "yes", "no"], default="auto")
    ap.add_argument("--include-fie", action="store_true", help="also keep sole proprietors (they carry a person's name)")
    ap.add_argument("--no-enrich", action="store_true", help="skip the register's general data, structure and the Tax Board figures")
    a = ap.parse_args()
    fetch(a.site, a.root, a.stats, a.refresh, a.max_age_days, a.keep_unmatched, a.include_fie, not a.no_enrich)
    sys.exit(0)
