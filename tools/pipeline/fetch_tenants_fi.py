#!/usr/bin/env python3
"""Finnish tenants for a tile (docs/finland-plan.md, step 3): the companies registered at the tile's
buildings and plots, from the Finnish Patent and Registration Office's open company data (PRH, the
YTJ register) and the Tax Administration's public corporate income tax data (Vero), both CC BY 4.0,
into the pack's tenants.json in the Estonian shape.

    python3 tools/pipeline/fetch_tenants_fi.py --site helsinki_senaatintori [--stats]

Sources, downloaded into data_raw/fi/prh/ and data_raw/fi/vero/:
  all_companies   PRH's daily bulk (a 96 MB zip of one 1.45 GB JSON array): every registered company
                  with its names, form, main line of business (TOL 2008, NACE with a fifth digit, like
                  EMTAK), visiting and postal addresses and its situations (bankruptcy, liquidation,
                  restructuring). Streamed once per download into a slim file of what a tile needs;
                  refreshed after a week
  Vero            the public corporate income tax data of the newest tax year (published each
                  November): taxable income and tax charged per business id; refreshed after 30 days

Matching: a company whose visiting address (else its postal one) is a building's address in the tile
- any of its Finnish and Swedish forms Ryhti gives, street and house number - in one of the tile's
municipalities is exact; one on the tile's streets whose number is outside it is "street".

Kept: legal persons doing business. Sole traders are not in the open data at all. Housing companies
(asunto-osakeyhtiö) and mutual property companies (keskinäinen kiinteistöosakeyhtiö) are left out:
they are the building's owners, not businesses in it (Porvoo's old town would be half housing
companies); the stats count them.

The Finnish figures are thinner than the Estonian: no staff count is published anywhere open, turnover
only in the 2.5 % of statements filed digitally (not read yet), and the tax is yearly. So `employees`
and `turnover` are null, `taxes` is the tax charged for `taxes_year`, and health rests on the
register's situations alone.
"""
import argparse, csv, glob, io, json, os, re, sys, time, unicodedata, urllib.request, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402
from emtak import group  # noqa: E402

UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
PRH_BULK = "https://avoindata.prh.fi/opendata-ytj-api/v3/all_companies"
VERO_PAGE = "https://www.vero.fi/tietoa-verohallinnosta/tilastot/avoin_dat/"
YTJ_LINK = "https://tietopalvelu.ytj.fi/yritys/{id}"
ATTRIBUTION = ("Yritys- ja yhteisötietojärjestelmä (YTJ): Patentti- ja rekisterihallitus (CC BY 4.0); "
               "yhteisöjen tuloverotuksen julkiset tiedot: Verohallinto (CC BY 4.0)")
SKIP_FORMS = {"2": "housing company", "10": "mutual property company"}   # PRH companyForms type codes
SITUATIONS = {"KONK": ("N", "konkurssi", "distressed"), "SELTILA": ("L", "selvitystila", "distressed"),
              "SANE": ("R", "yrityssaneeraus", "watch")}
SLIM_VERSION = 1
PRH_MAX_AGE = 7
VERO_MAX_AGE = 30


def log(msg):
    print(f"[fetch_tenants_fi] {msg}", flush=True)


def _tls():
    import fetch_cadastre_fi   # certifi's roots (the macOS store lacks some Finnish agencies' chains)
    return fetch_cadastre_fi._tls()


def _fetch(url, path, max_age_days):
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < max_age_days * 86400:
        return path
    log(f"downloading {url}")
    tmp = path + ".part"
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=1800, context=_tls()) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, path)
    return path


# ------------------------------------------------------------------------------------------ PRH
def _stream(fileobj):
    """The objects of one huge JSON array, a few MB at a time: the bulk never fits in memory whole."""
    dec = json.JSONDecoder()
    buf, pos = "", 0
    text = io.TextIOWrapper(fileobj, encoding="utf-8")
    while True:
        chunk = text.read(16 << 20)
        buf, pos = buf[pos:] + chunk, 0
        while True:
            while pos < len(buf) and buf[pos] in "[, \n\r\t]":
                pos += 1
            if pos >= len(buf):
                break
            try:
                obj, end = dec.raw_decode(buf, pos)
            except ValueError:
                break
            yield obj
            pos = end
        if not chunk:
            return


def _fi(descriptions):
    return next((d.get("description") for d in descriptions or [] if d.get("languageCode") == "1"), None)


def slim(c):
    """What a tile needs of one PRH record."""
    names = [n for n in c.get("names") or [] if n.get("type") == "1" and not n.get("endDate")] or (c.get("names") or [])[:1]
    forms = [f for f in c.get("companyForms") or [] if not f.get("endDate")] or (c.get("companyForms") or [])[:1]
    line = c.get("mainBusinessLine") or {}
    addrs = []
    for a in c.get("addresses") or []:
        offices = a.get("postOffices") or []
        muni = next((o.get("municipalityCode") for o in offices if o.get("municipalityCode")), None)
        if a.get("street") and a.get("buildingNumber"):
            addrs.append([a.get("type"), a["street"], a["buildingNumber"], a.get("entrance") or "", a.get("postCode"), muni])
    return {"id": (c.get("businessId") or {}).get("value"), "name": names[0]["name"] if names else None,
            "form": forms[0].get("type") if forms else None, "form_text": _fi(forms[0].get("descriptions")) if forms else None,
            "since": c.get("registrationDate") or (c.get("businessId") or {}).get("registrationDate"), "end": c.get("endDate"),
            "situations": sorted({s.get("type") for s in c.get("companySituations") or [] if not s.get("endDate")} - {None}),
            "tol": line.get("type"), "tol_text": _fi(line.get("descriptions")), "web": (c.get("website") or {}).get("url"),
            "addresses": addrs}


def prh_slim():
    """The slim file of the newest bulk (JSON lines), made once per download."""
    d = paths.raw("fi", "prh")
    zpath = _fetch(PRH_BULK, os.path.join(d, "all_companies.zip"), PRH_MAX_AGE)
    stamp = time.strftime("%Y%m%d", time.localtime(os.path.getmtime(zpath)))
    out = os.path.join(d, f"companies_{stamp}.v{SLIM_VERSION}.slim.jsonl")
    if os.path.exists(out):
        return out
    t0, n = time.time(), 0
    with zipfile.ZipFile(zpath) as z, z.open(z.namelist()[0]) as raw, open(out + ".part", "w", encoding="utf-8") as f:
        for c in _stream(raw):
            s = slim(c)
            if s["id"] and s["addresses"]:
                f.write(json.dumps(s, ensure_ascii=False, separators=(",", ":")) + "\n")
                n += 1
    os.replace(out + ".part", out)
    for old in glob.glob(os.path.join(d, "companies_*.slim.jsonl")):
        if old != out:
            os.remove(old)
    log(f"slimmed the PRH bulk: {n:,} companies with a street address in {time.time() - t0:.0f} s")
    return out


# ------------------------------------------------------------------------------------------ Vero
def vero_csv():
    """The newest tax year's public corporate income tax file (not the corrections file)."""
    d = paths.raw("fi", "vero")
    have = sorted(glob.glob(os.path.join(d, "tuloverotus_*.csv")))
    if have and time.time() - os.path.getmtime(have[-1]) < VERO_MAX_AGE * 86400:
        return have[-1]
    try:
        page = urllib.request.urlopen(urllib.request.Request(VERO_PAGE, headers={"User-Agent": "Mozilla/5.0"}), timeout=60,
                                      context=_tls()).read().decode("utf-8", "replace")
        links = {}
        for href in re.findall(r'href="([^"]+\.csv)"', page):
            low = urllib.request.unquote(href).lower()
            m = re.search(r"(20\d\d)", low.rsplit("/", 1)[-1])
            if m and "tuloverotus" in low and "muutos" not in low:
                links[int(m.group(1))] = urllib.request.urljoin(VERO_PAGE, href)
        year = max(links)
        return _fetch(links[year], os.path.join(d, f"tuloverotus_{year}.csv"), VERO_MAX_AGE)
    except Exception as e:  # noqa: BLE001 - an older file still does
        if have:
            log(f"Vero's page unavailable ({e}); keeping {os.path.basename(have[-1])}")
            return have[-1]
        raise


def _money(s):
    s = (s or "").strip().replace("\xa0", "").replace(" ", "").replace(",", ".")
    try:
        return int(round(float(s)))
    except ValueError:
        return None


def vero_rows(path, wanted):
    """{business id: (year, taxable income, tax charged)} for the wanted ids. ISO-8859-1, ';', decimal comma."""
    out = {}
    with open(path, encoding="iso-8859-1", newline="") as f:
        for r in csv.DictReader(f, delimiter=";"):
            r = {k.split("|")[0].strip(): v for k, v in r.items() if k}   # "Y-tunnus | FO-nummer": the Finnish half
            yid = (r.get("Y-tunnus") or "").strip()
            if yid in wanted:
                year = (r.get("Verovuosi") or "").strip()
                out[yid] = (int(year) if year.isdigit() else None, _money(r.get("Verotettava tulo")),
                            _money(r.get("Maksuunpannut verot yhteensä")))
    return out


# ------------------------------------------------------------------------------------------ addresses
def _fold(s):
    s = unicodedata.normalize("NFC", str(s or "")).lower().replace("\xa0", " ")
    return " ".join(s.split())


_NUM = re.compile(r"^(\d+)\s*([a-zåäö]?)\b")


def house_numbers(num):
    """'15' -> ['15']; '13a' / '13 A' -> ['13a', '13']; '16-18' -> ['16', '18', '17']: the forms a
    register writes, most specific first."""
    s = _fold(num)
    out = []
    for part in re.split(r"\s*[-–]\s*", s)[:2]:
        m = _NUM.match(part)
        if m:
            if m.group(2):
                out.append(m.group(1) + m.group(2))
            out.append(m.group(1))
    nums = [int(x) for x in out if x.isdigit()]
    if len(nums) == 2 and 0 < nums[1] - nums[0] <= 10:
        out += [str(n) for n in range(nums[0] + 1, nums[1])]
    return list(dict.fromkeys(out))


def split_address(text):
    """'Aleksanterinkatu 15' -> ('aleksanterinkatu', ['15']); 'Mariankatu 13a' -> ('mariankatu', ['13a', '13'])."""
    m = re.match(r"^(.*?\D)\s+(\d.*)$", str(text or "").strip())
    if not m:
        return None, []
    return _fold(m.group(1)), house_numbers(m.group(2))


def build_index(parcels, buildings):
    idx = {"b": {}, "p": {}, "streets": set(), "tunnus": {u["tunnus"] for u in parcels},
           "munis": {str(u.get("ehak")) for u in parcels if u.get("ehak")}}
    for b in buildings:
        for a in set([b.get("address")] + list(b.get("addresses") or [])):
            street, nums = split_address(a)
            if street:
                idx["streets"].add(street)
                for n in nums:
                    idx["b"].setdefault((street, n), []).append(b)
    for u in parcels:
        street, nums = split_address(u.get("address"))
        if street:
            idx["streets"].add(street)
            for n in nums:
                idx["p"].setdefault((street, n), u["tunnus"])
    return idx


def _best(bs):
    return max(bs, key=lambda b: (b.get("kind") != "outbuilding", b.get("w", 0) * b.get("d", 0)))


def match(c, idx):
    """(tunnus, building id, match, address text) for a slim PRH record: the visiting address first."""
    street_hit = None
    for a in sorted(c["addresses"], key=lambda a: a[0] != 1):
        _type, street, number, _entrance, _post, muni = a
        if idx["munis"] and muni and str(muni) not in idx["munis"]:
            continue
        s = _fold(street)
        for n in house_numbers(number):
            if (s, n) in idx["b"]:
                b = _best(idx["b"][(s, n)])
                tun = next((t for t in b.get("cadastral") or [] if t in idx["tunnus"]), None)
                return tun, b["id"], "exact", f"{street.title()} {number}"
            if (s, n) in idx["p"]:
                return idx["p"][(s, n)], None, "exact", f"{street.title()} {number}"
        if s in idx["streets"] and street_hit is None:
            street_hit = f"{street.title()} {number}"
    if street_hit:
        return None, None, "street", street_hit
    return None, None, "none", None


# ------------------------------------------------------------------------------------------ the tile
def fetch(site, root=paths.ROOT, stats=False, today=None):
    site_dir = os.path.join(root, "sites", site)
    parcels = json.load(open(os.path.join(site_dir, "parcels.json"))).get("parcels", [])
    bpath = os.path.join(site_dir, "buildings.json")
    buildings = json.load(open(bpath)).get("buildings", []) if os.path.exists(bpath) else []
    idx = build_index(parcels, buildings)
    today = today or time.strftime("%Y-%m-%d")
    t0 = time.time()
    st = {"scanned": 0, "exact": 0, "street": 0, "dissolved": 0, "skipped_forms": {}}

    cands = {}
    with open(prh_slim(), encoding="utf-8") as f:
        for line in f:
            st["scanned"] += 1
            c = json.loads(line)
            tunnus, bid, m, addr = match(c, idx)
            if m == "none":
                continue
            if c.get("end"):
                st["dissolved"] += 1
                continue
            if c.get("form") in SKIP_FORMS:
                k = SKIP_FORMS[c["form"]]
                st["skipped_forms"][k] = st["skipped_forms"].get(k, 0) + 1
                continue
            st[m] += 1
            cands[c["id"]] = (c, tunnus, bid, m, addr)
    log(f"{len(cands)} companies at the tile's addresses ({st['exact']} exact, {st['street']} on its streets) of {st['scanned']:,}; "
        f"left out {st['skipped_forms']}")

    vpath = vero_csv()
    taxes = vero_rows(vpath, set(cands))
    out = []
    for yid, (c, tunnus, bid, m, addr) in cands.items():
        sit = next((SITUATIONS[s] for s in ("KONK", "SELTILA", "SANE") if s in c["situations"]), None)
        status, status_text, verdict = sit if sit else ("R", "rekisterissä", "sound")
        tol = c.get("tol")
        sector = group(tol, 2) if tol else ""
        year, income, tax = taxes.get(yid, (None, None, None))
        out.append({
            "registry_code": yid, "name": c.get("name"), "legal_form": c.get("form_text"), "status": status, "status_text": status_text,
            "active": status == "R", "since": c.get("since"), "address": addr, "ehak": next((a[5] for a in c["addresses"] if a[5]), None),
            "tunnus": tunnus, "building_id": bid, "match": m, "via": "address" if m == "exact" else None,
            "link": YTJ_LINK.format(id=yid), "country": "fi",
            "emtak": {"code": tol, "text": c.get("tol_text"), "nace": (tol[:2] + "." + tol[2:4]) if tol and len(tol) >= 4 else tol,
                      "section": sector} if tol else None,
            "sector": sector or None, "capital": None, "web": None,
            "employees": None, "turnover": None, "turnover_year": None,
            "taxes": tax, "taxes_year": year if tax is not None else None, "taxable_income": income,
            "employees_hist": [], "quarters": [],
            "board_size": None, "shareholders": None, "owner_managed": None, "owners": [],
            "deleted": None, "report_overdue": False, "health": verdict, "health_why": {"rule": "status"} if sit else None,
        })
    rank = {"exact": 0, "street": 1}
    out.sort(key=lambda t: (rank[t["match"]], t["name"] or ""))
    st["kept"] = len(out)
    st["with_tax"] = sum(1 for t in out if t["taxes"] is not None)
    st["tax_positive"] = sum(1 for t in out if (t["taxes"] or 0) > 0)
    st["health"] = {h: sum(1 for t in out if t["health"] == h) for h in ("sound", "watch", "distressed")}
    st["sectors"] = {}
    for t in out:
        if t["sector"]:
            st["sectors"][t["sector"]] = st["sectors"].get(t["sector"], 0) + 1
    st["elapsed_s"] = round(time.time() - t0, 1)
    json.dump({"attribution": ATTRIBUTION, "source": "avoindata.prh.fi (YTJ bulk), vero.fi (public corporate income tax data)",
               "sources": {"register": os.path.basename(prh_slim()), "vero": os.path.basename(vpath)},
               "fetched": today, "register_date": today, "ehak": sorted(idx["munis"]), "country": "fi", "stats": st, "tenants": out},
              open(os.path.join(site_dir, "tenants.json"), "w"), ensure_ascii=False, indent=0)
    log(f"wrote sites/{site}/tenants.json: {len(out)} companies ({sum(1 for t in out if t['match'] == 'exact')} exact); "
        f"{st['with_tax']} in Vero's {os.path.basename(vpath)}, {st['tax_positive']} paying tax; health {st['health']}; {st['elapsed_s']} s")
    if stats:
        log(f"sectors {dict(sorted(st['sectors'].items(), key=lambda kv: -kv[1]))}; {st['dissolved']} dissolved")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=paths.ROOT)
    ap.add_argument("--stats", action="store_true")
    a = ap.parse_args()
    fetch(a.site, a.root, a.stats)
