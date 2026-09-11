#!/usr/bin/env python3
"""Latvian tenants for a tile (docs/latvia-plan.md, step 3): the companies registered at the tile's
buildings and plots, from the Enterprise Register (Uzņēmumu reģistrs, UR) and the State Revenue
Service (VID) open data, all CC0, into the pack's tenants.json in the Estonian shape.

    python3 tools/pipeline/fetch_tenants_lv.py --site riga_vecpilseta [--stats]

Sources (data.gov.lv, downloaded into data_raw/lv/ur/ and data_raw/lv/vid/, refreshed after a week):
  register.csv                 every entity: number, name, legal form, registration and termination
                               dates, address and its address-register code (`addressid`)
  liquidations.csv, insolvency_legal_person_proceeding.csv   liquidation and insolvency, for the status
  officers.csv, members.csv, stockholders.csv   board and owners, kept as structure only: counts and
                               opaque ids (a person's name, masked code and birth date hashed; a company's
                               own registration number) that let `Links` tie companies sharing an owner
  financial_statements.csv, income_statements.csv   annual reports: year, employees, net turnover
  VID quarterly file (cet_<year>Q<q>.csv, the archive step 0 keeps) and the three-year file
                               taxes paid and average employees; the NACE code gives the sector

Matching: a company whose address code is a building's or a parcel's is exact; otherwise its address
("Kaļķu iela 15 - 8": the premises after " - " dropped, alternatives after ";" tried) is compared
with the tile's building and parcel addresses in the same town. Kept: legal persons only; sole
traders (IK, IND) carry a person's name and farms (ZEM) are family holdings, both skipped.
Terminated entities are left out; in liquidation or insolvency they stay, as empty premises.

The Latvian figures differ from the Estonian: VID publishes taxes and employees but no turnover,
which comes from the latest annual report instead (`turnover_year`), and `taxes` is the latest year
VID has in full (`taxes_year`). The health rules read the same way: register status, a year of zero
taxes while employing, an overdue annual report, turnover down 40 % on the year before.
"""
import argparse, csv, glob, json, os, re, sys, time, unicodedata, urllib.request, uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402
from emtak import group  # noqa: E402

UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
VID_ANNUAL = "komersantu-ieprieksejos-tris-taksacijas-gados-samaksato-vid-administreto-nodoklu-kopsummas"
VID_QUARTER = "nodoklu-maksataju-taksacijas-ceturksni-samaksato-vid-administreto-nodoklu-kopsummas"
ATTRIBUTION = "Uzņēmumu reģistra atvērtie dati (CC0); samaksāto VID administrēto nodokļu kopsummas: Valsts ieņēmumu dienests (CC0)"
SKIP_TYPES = {"IK", "IND", "ZEM"}          # sole traders and farms: a person behind the name
BOARD_BODIES = {"EXECUTIVE_BOARD", "EXECUTIVE_BODY", "MANAGEMENT_BODY", ""}
PERSON_NS = uuid.uuid5(uuid.NAMESPACE_URL, "vakuraamat/lv-person")
MAX_AGE_DAYS = 7


def log(msg):
    print(f"[fetch_tenants_lv] {msg}", flush=True)


# ------------------------------------------------------------------------------------------ files
def _resource_url(name):
    q = f"https://data.gov.lv/dati/api/3/action/resource_search?query=url:{name}&limit=10"
    for r in json.load(urllib.request.urlopen(urllib.request.Request(q, headers=UA), timeout=60))["result"]["results"]:
        if r["url"].startswith("https://data.gov.lv/") and r["url"].endswith("/" + name):
            return r["url"]
    raise RuntimeError(f"data.gov.lv has no {name}")


def _package_csv(slug):
    q = f"https://data.gov.lv/dati/api/3/action/package_show?id={slug}"
    res = json.load(urllib.request.urlopen(urllib.request.Request(q, headers=UA), timeout=60))["result"]["resources"]
    return next(r["url"] for r in res if r["url"].lower().endswith(".csv"))


def _fetch(url, path, max_age_days=MAX_AGE_DAYS):
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < max_age_days * 86400:
        return path
    log(f"downloading {os.path.basename(path)}")
    tmp = path + ".part"
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, path)
    return path


def ur_file(name):
    return _fetch(_resource_url(name), os.path.join(paths.raw("lv", "ur"), name))


def vid_files():
    """The three-year file and every archived quarter (the quarterly file holds only the latest one,
    so each download is kept under its own quarter's name: cet_2026Q2.csv)."""
    d = paths.raw("lv", "vid")
    annual = sorted(glob.glob(os.path.join(d, "nm_3gadi_*.csv")))
    if not annual:
        annual = [_fetch(_package_csv(VID_ANNUAL), os.path.join(d, "nm_3gadi_latest.csv"), 90)]
    try:   # archive the current quarter under its name if it is not there yet
        tmp = _fetch(_package_csv(VID_QUARTER), os.path.join(d, "cet_latest.csv"), MAX_AGE_DAYS)
        with open(tmp, encoding="utf-8-sig") as f:
            row = next(csv.DictReader(f), {})
        m = re.match(r"(\d{4})\. gada (\d)\. ceturksnis", row.get("Taksacijas_gads_ceturksnis", ""))
        if m:
            named = os.path.join(d, f"cet_{m.group(1)}Q{m.group(2)}.csv")
            if not os.path.exists(named):
                os.replace(tmp, named)
                log(f"archived VID quarter {m.group(1)} Q{m.group(2)}")
    except Exception as e:  # noqa: BLE001 - the archive already held may do
        log(f"VID quarterly file unavailable ({e})")
    return annual, sorted(glob.glob(os.path.join(d, "cet_*Q*.csv")))


def rows(path, delimiter=";"):
    with open(path, encoding="utf-8-sig", newline="") as f:
        yield from csv.DictReader(f, delimiter=delimiter)


# ------------------------------------------------------------------------------------------ addresses
def _fold(s):
    return unicodedata.normalize("NFC", str(s or "")).lower().replace(" ", " ").strip()


_HOUSE = re.compile(r"^(?P<street>.*?\D)\s*(?P<num>\d+[a-z]?(?:/\d+[a-z]?)?(?:\s*k-\d+)?)$")


def address_keys(text):
    """'Kaļķu iela 15 - 8' -> [('kaļķu iela', '15')]; 'Tirgoņu iela 11/13;15' -> both numbers;
    'Republikas laukums 2A' -> [('republikas laukums', '2a')]. The premises after ' - ' are dropped."""
    keys, street = [], None
    for part in _fold(text).split(";"):
        part = re.sub(r"\s+-\s+.*$", "", part).strip().strip(",")
        part = re.sub(r",?\s*ist\.nr\..*$", "", part).strip()
        if not part:
            continue
        m = _HOUSE.match(part)
        if m:
            street = " ".join(m.group("street").split()).strip(" ,")
            keys.append((street, m.group("num").replace(" ", "")))
        elif street and re.fullmatch(r"\d+[a-z]?(?:/\d+[a-z]?)?", part):
            keys.append((street, part))   # "11/13;15": the bare number continues the street
    return keys


def split_register_address(addr):
    """('rīga', 'Kaļķu iela 15 - 8') from 'Rīga, Kaļķu iela 15 - 8'; the town is the first segment
    that is not a municipality or parish, the street part the last segment."""
    segs = [s.strip() for s in (addr or "").split(",") if s.strip()]
    if not segs:
        return "", ""
    town = next((s for s in segs if not s.endswith(("nov.", "pag.", "novads", "pagasts"))), segs[0])
    return _fold(town), segs[-1]


# ------------------------------------------------------------------------------------------ people
def holder_id(row):
    """An owner or board member as an opaque id: a company's own registration number, or a hash of
    what the register says of a person (name, masked code, birth date). Nothing readable is kept."""
    code = (row.get("legal_entity_registration_number") or "").strip()
    if row.get("entity_type") == "LEGAL_ENTITY" and code.isdigit():
        return code
    key = "|".join((row.get("name") or "", row.get("latvian_identity_number_masked") or "", row.get("birth_date") or "")).casefold()
    return str(uuid.uuid5(PERSON_NS, key)) if key.strip("|") else None


# ------------------------------------------------------------------------------------------ figures
# The long legal forms a name can open with, and the abbreviations a sign uses (longest first)
FORM_ABBREV = [("pašvaldības sabiedrība ar ierobežotu atbildību", "PSIA"), ("valsts sabiedrība ar ierobežotu atbildību", "VSIA"),
               ("sabiedrība ar ierobežotu atbildību", "SIA"), ("valsts akciju sabiedrība", "VAS"), ("pašvaldības akciju sabiedrība", "PAS"),
               ("akciju sabiedrība", "AS"), ("kooperatīvā sabiedrība", "KS")]


def display_name(r):
    """The name as a sign would carry it: 'Sabiedrība ar ierobežotu atbildību "eDirect SAAS"' is
    'SIA "eDirect SAAS"', 'Valsts sabiedrība ar ierobežotu atbildību "Rīgas..."' is 'VSIA "Rīgas..."'
    (the legal form stands in its own column); a name that is already short stays as it is."""
    name = (r.get("name") or "").strip()
    quoted = (r.get("name_in_quotes") or "").strip()
    before = (r.get("name_before_quotes") or "").strip().casefold()
    if quoted and before:
        for long, short in FORM_ABBREV:
            if before == long:
                after = (r.get("name_after_quotes") or "").strip()
                return f'{short} "{quoted}"' + (f" {after}" if after else "")
    return name


def _num(s, scale=1.0):
    s = (s or "").strip().replace(",", ".")
    try:
        return int(round(float(s) * scale))
    except ValueError:
        return None


def health(status, legal_protection, annual_taxes, reports, report_overdue):
    """(verdict, why) by the Estonian rules, read from the Latvian figures."""
    if status in ("N", "L"):
        return "distressed", {"rule": "status"}
    if legal_protection:
        return "watch", {"rule": "status"}
    if annual_taxes:
        year, taxes, employees = annual_taxes[-1]
        if taxes == 0 and (employees or 0) > 0:
            return "distressed", {"rule": "zero_taxes"}
    if report_overdue:
        return "watch", {"rule": "report"}
    turn = [(y, t) for y, t, _e in reports if t is not None]
    if len(turn) >= 2 and turn[-1][0] == turn[-2][0] + 1:
        (ya, a), (yb, b) = turn[-2], turn[-1]
        if a > 0 and b < a * 0.6:
            return "watch", {"rule": "turnover", "from": [ya, a], "to": [yb, b]}
    return "sound", None


# ------------------------------------------------------------------------------------------ the tile
def build_index(parcels, buildings):
    tunnus_set = {u["tunnus"] for u in parcels}
    idx = {"var_b": {}, "var_p": {}, "key_b": {}, "key_p": {}, "streets": set(), "tunnus_set": tunnus_set,
           "towns": {_fold(u.get("settlement")) for u in parcels if u.get("settlement")}}
    for u in parcels:
        if u.get("ads_oid"):
            idx["var_p"][str(u["ads_oid"])] = u["tunnus"]
        for k in address_keys(u.get("address")):
            idx["key_p"].setdefault(k, u["tunnus"])
            idx["streets"].add(k[0])
    for b in buildings:
        if (b.get("ads") or {}).get("var_code"):
            idx["var_b"][str(b["ads"]["var_code"])] = b
        for a in set([b.get("address")] + list(b.get("addresses") or [])):
            for k in address_keys(a):
                idx["key_b"].setdefault(k, []).append(b)
                idx["streets"].add(k[0])
    return idx


def _parcel_of(b, idx):
    return next((c for c in b.get("cadastral") or [] if c in idx["tunnus_set"]), None)


def _best(bs):
    return max(bs, key=lambda b: (b.get("kind") != "outbuilding", b.get("w", 0) * b.get("d", 0)))


def match(row, idx):
    """(tunnus, building_id, match, via) for a register row."""
    aid = (row.get("addressid") or "").strip()
    if aid in idx["var_b"]:
        b = idx["var_b"][aid]
        return _parcel_of(b, idx), b["id"], "exact", "var"
    if aid in idx["var_p"]:
        return idx["var_p"][aid], None, "exact", "var"
    town, street_part = split_register_address(row.get("address"))
    if idx["towns"] and town not in idx["towns"]:
        return None, None, "none", None
    keys = address_keys(street_part)
    for k in keys:
        if k in idx["key_b"]:
            b = _best(idx["key_b"][k])
            return _parcel_of(b, idx), b["id"], "exact", "address"
        if k in idx["key_p"]:
            return idx["key_p"][k], None, "exact", "address"
    if any(k[0] in idx["streets"] for k in keys):
        return None, None, "street", None
    return None, None, "none", None


def fetch(site, root=paths.ROOT, stats=False, today=None):
    site_dir = os.path.join(root, "sites", site)
    pd = json.load(open(os.path.join(site_dir, "parcels.json")))
    parcels = pd.get("parcels", [])
    bpath = os.path.join(site_dir, "buildings.json")
    buildings = json.load(open(bpath)).get("buildings", []) if os.path.exists(bpath) else []
    idx = build_index(parcels, buildings)
    today = today or time.strftime("%Y-%m-%d")
    t0 = time.time()
    st = {"scanned": 0, "skipped_person": 0, "terminated": 0, "exact_var": 0, "exact_address": 0, "street": 0}

    # --- the companies at the tile's addresses
    cands = {}
    for r in rows(ur_file("register.csv")):
        st["scanned"] += 1
        tunnus, bid, m, via = match(r, idx)
        if m == "none":
            continue
        if r.get("terminated"):
            st["terminated"] += 1
            continue
        if (r.get("type") or "") in SKIP_TYPES:
            st["skipped_person"] += 1
            continue
        if m == "exact":
            st["exact_" + via] += 1
        else:
            st["street"] += 1
        cands[r["regcode"]] = {"row": r, "tunnus": tunnus, "building_id": bid, "match": m, "via": via}
    codes = set(cands)
    log(f"{len(codes)} companies at the tile's addresses ({st['exact_var']} by address code, {st['exact_address']} by address, "
        f"{st['street']} on its streets) of {st['scanned']:,}")

    # --- status
    liquid = {r["legal_entity_registration_number"]: r.get("liquidation_type_text") or "likvidācija"
              for r in rows(ur_file("liquidations.csv")) if r["legal_entity_registration_number"] in codes}
    insolvent, protected = {}, set()
    for r in rows(ur_file("insolvency_legal_person_proceeding.csv")):
        c = r.get("debtor_registration_number")
        if c in codes and not r.get("proceeding_ended_on"):
            if r.get("proceeding_form") == "INSOLVENCY":
                insolvent[c] = "maksātnespējas process"
            else:
                protected.add(c)

    # --- board and owners, as structure
    board, owners, holders = {}, {}, {}
    for r in rows(ur_file("officers.csv")):
        c = r.get("at_legal_entity_registration_number")
        if c in codes and (r.get("governing_body") or "") in BOARD_BODIES:
            h = holder_id(r)
            if h:
                board.setdefault(c, set()).add(h)
    for name in ("members.csv", "stockholders.csv"):
        for r in rows(ur_file(name)):
            c = r.get("at_legal_entity_registration_number")
            if c in codes and r.get("entity_type") not in ("DEPOSITORY", None):
                h = holder_id(r)
                if h:
                    owners.setdefault(c, set()).add(h)
                holders[c] = holders.get(c, 0) + 1

    # --- annual reports
    stmts = {}   # statement id -> (code, year, employees, scale)
    for r in rows(ur_file("financial_statements.csv")):
        c = r.get("legal_entity_registration_number")
        if c in codes:
            scale = 1000.0 if r.get("rounded_to_nearest") == "THOUSANDS" else 1.0
            stmts[r["id"]] = (c, int(r["year"]) if (r.get("year") or "").isdigit() else None, _num(r.get("employees")), scale)
    reports = {}
    for r in rows(ur_file("income_statements.csv")):
        s = stmts.get(r.get("statement_id"))
        if s and s[1]:
            reports.setdefault(s[0], {})[s[1]] = (s[1], _num(r.get("net_turnover"), s[3]), s[2])
    for sid, (c, y, emp, _scale) in stmts.items():   # a report without an income statement still dates the filing
        if y and y not in reports.get(c, {}):
            reports.setdefault(c, {})[y] = (y, None, emp)

    # --- VID: taxes and employees
    annual_paths, quarter_paths = vid_files()
    annual, nace = {}, {}
    for p in annual_paths:
        for r in rows(p, ","):
            c = r.get("Registracijas_kods")
            if c in codes and (r.get("Taksacijas_gads") or "").isdigit():
                annual.setdefault(c, {})[int(r["Taksacijas_gads"])] = (
                    int(r["Taksacijas_gads"]), _num(r.get("Samaksato_VID_administreto_nodoklu_kopsumma_tukst_EUR"), 1000.0),
                    _num(r.get("Videjais_nodarbinato_personu_skaits_cilv")))
                if (r.get("Pamatdarbibas_NACE_kods") or "").strip():
                    nace[c] = r["Pamatdarbibas_NACE_kods"].strip()
    quarters = {}
    for p in quarter_paths:
        for r in rows(p, ","):
            c = r.get("Registracijas_kods")
            m = re.match(r"(\d{4})\. gada (\d)\. ceturksnis", r.get("Taksacijas_gads_ceturksnis") or "")
            if c in codes and m:
                quarters.setdefault(c, {})[(int(m.group(1)), int(m.group(2)))] = (
                    _num(r.get("Samaksato_VID_administreto_nodoklu_kopsumma_tukst_EUR"), 1000.0),
                    _num(r.get("Videjais_nodarbinato_personu_skaits_cilv")))

    # --- the rows
    year_now = int(today[:4])
    due_year = year_now - 1 if today >= f"{year_now}-12-31" else year_now - 2   # a report is due by the next summer
    out = []
    for c, cand in cands.items():
        r = cand["row"]
        status = "N" if c in insolvent else ("L" if c in liquid else "R")
        status_text = insolvent.get(c) or liquid.get(c) or ("tiesiskās aizsardzības process" if c in protected else "reģistrēts")
        rep = sorted((reports.get(c) or {}).values())
        ann = sorted((annual.get(c) or {}).values())
        qs = sorted((quarters.get(c) or {}).items())
        last_q = qs[-1][1] if qs else None
        employees = (last_q[1] if last_q and last_q[1] is not None else
                     (ann[-1][2] if ann and ann[-1][2] is not None else (rep[-1][2] if rep else None)))
        turn = [x for x in rep if x[1] is not None]
        full_q = [k for k, _v in qs]
        years_q = sorted({y for y, _q in full_q if sum(1 for yy, _ in full_q if yy == y) == 4})
        if years_q:
            taxes_year, taxes = years_q[-1], sum(v[0] or 0 for k, v in qs if k[0] == years_q[-1])
        elif ann:
            taxes_year, taxes = ann[-1][0], ann[-1][1]
        else:
            taxes_year, taxes = None, None
        report_overdue = bool(rep) and rep[-1][0] < due_year and status == "R"
        verdict, why = health(status, c in protected, ann, rep, report_overdue)
        b, o = board.get(c, set()), owners.get(c, set())
        code4 = nace.get(c)
        sector = group(code4, 2) if code4 else ""
        out.append({
            "registry_code": c, "name": display_name(r), "legal_form": r.get("type_text"), "status": status, "status_text": status_text,
            "active": status == "R", "since": r.get("registered") or None, "address": split_register_address(r.get("address"))[1],
            "ehak": r.get("atvk"), "tunnus": cand["tunnus"], "building_id": cand["building_id"], "match": cand["match"], "via": cand["via"],
            "link": None, "country": "lv",
            "emtak": {"code": code4, "text": None, "nace": (code4[:2] + "." + code4[2:]) if code4 and len(code4) >= 3 else code4, "section": sector} if code4 else None,
            "sector": sector or None, "capital": None, "web": None,
            "employees": employees, "turnover": turn[-1][1] if turn else None, "turnover_year": turn[-1][0] if turn else None,
            "taxes": taxes, "taxes_year": taxes_year,
            "employees_hist": [[y, e] for y, _t, e in ann if e is not None] or [[y, e] for y, _t, e in rep if e is not None],
            "quarters": [[k[0], k[1], None, v[1]] for k, v in qs[-8:]],
            "board_size": len(b) if c in board else None, "shareholders": holders.get(c) if c in holders else None,
            "owner_managed": bool(b & o) if b and o else None, "owners": sorted(b | o),
            "deleted": None, "report_overdue": report_overdue, "health": verdict, "health_why": why,
        })
    rank = {"exact": 0, "street": 1}
    out.sort(key=lambda t: (rank[t["match"]], t["name"] or ""))
    st["kept"] = len(out)
    st["exact"] = sum(1 for t in out if t["match"] == "exact")
    st["with_tax"] = sum(1 for t in out if t["taxes"] is not None)
    st["with_report"] = sum(1 for t in out if t["turnover"] is not None)
    st["health"] = {h: sum(1 for t in out if t["health"] == h) for h in ("sound", "watch", "distressed")}
    st["sectors"] = {}
    for t in out:
        if t["sector"]:
            st["sectors"][t["sector"]] = st["sectors"].get(t["sector"], 0) + 1
    st["elapsed_s"] = round(time.time() - t0, 1)
    atvk = sorted({t["ehak"] for t in out if t.get("ehak")})
    json.dump({"attribution": ATTRIBUTION, "source": "data.gov.lv: Uzņēmumu reģistrs, Valsts ieņēmumu dienests", "sources": {
               "register": "register.csv", "vid_quarters": [os.path.basename(p) for p in quarter_paths],
               "vid_annual": [os.path.basename(p) for p in annual_paths]},
               "fetched": today, "register_date": today, "ehak": atvk, "country": "lv", "stats": st, "tenants": out},
              open(os.path.join(site_dir, "tenants.json"), "w"), ensure_ascii=False, indent=0)
    log(f"wrote sites/{site}/tenants.json: {len(out)} companies ({st['exact']} exact, {len(out) - st['exact']} on the tile's streets); "
        f"{st['with_tax']} with VID taxes, {st['with_report']} with a turnover; health {st['health']}; {st['elapsed_s']} s")
    if stats:
        log(f"sectors {dict(sorted(st['sectors'].items(), key=lambda kv: -kv[1]))}; skipped {st['skipped_person']} sole traders and farms, "
            f"{st['terminated']} terminated")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=paths.ROOT)
    ap.add_argument("--stats", action="store_true")
    a = ap.parse_args()
    fetch(a.site, a.root, a.stats)
