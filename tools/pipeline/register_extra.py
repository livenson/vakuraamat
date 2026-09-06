"""What the e-Business Register and the Tax Board publish beyond a company's name and address, for the
tile's tenants (tools/pipeline/fetch_tenants.py calls `enrich`).

Sources (all open data, credited in THIRD_PARTY.md):
  register general data  ettevotja_rekvisiidid__yldandmed.json.zip   EMTAK activity, capital, web address, annual-report
                                                                      employee counts, deletion date
  register persons       ettevotja_rekvisiidid__kaardile_kantud_isikud.json.zip   board members (roles, hashed ids)
  register shareholders  ettevotja_rekvisiidid__osanikud.json.zip     shareholders (hashed ids, stakes)
  Tax Board              tasutud_maksud_kaesolev_aasta.csv, tasutud_maksud_varasemad_aastad.csv
                                                                      quarterly taxes, turnover and employees per company
The register dumps are 30-230 MB pretty-printed JSON arrays; the first use after a download slims each one
into `<name>.slim.jsonl` (one small record per company, only the fields below), so a tile job reads a few
tens of MB. People are kept as structure only: role counts and the register's own `isikukood_hash`
(a stable anonymous id, used to link companies that share an owner); no names, e-mails or phones.
"""
import csv, io, json, os, re, time, urllib.request, zipfile

from emtak import group, group_of_tax_words

REGISTER_BASE = "https://avaandmed.ariregister.rik.ee/sites/default/files/avaandmed/"
GENERAL = "ettevotja_rekvisiidid__yldandmed.json.zip"
PERSONS = "ettevotja_rekvisiidid__kaardile_kantud_isikud.json.zip"
SHAREHOLDERS = "ettevotja_rekvisiidid__osanikud.json.zip"
TAX_FILES = {"tasutud_maksud_kaesolev_aasta.csv": "https://ncfailid.emta.ee/s/DFHQjB2Rsq3CK7p/download/tasutud_maksud_kaesolev_aasta.csv",
             "tasutud_maksud_varasemad_aastad.csv": "https://ncfailid.emta.ee/s/bCszrta8THHA9xn/download/tasutud_maksud_varasemad_aastad.csv"}
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
BOARD_ROLES = {"JUHL", "JUHE", "JUHT", "TEGJ", "PROK"}   # board member, chair, managing director, procurator


def log(msg):
    print(f"[register_extra] {msg}", flush=True)


def download(url, path, max_age_days=7, refresh=False):
    """Fetch `url` to `path` unless a fresh copy (by the sidecar meta) exists. Returns the download date."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    meta_path = path + ".meta.json"
    if os.path.exists(path) and os.path.exists(meta_path) and not refresh:
        meta = json.load(open(meta_path))
        age = (time.time() - time.mktime(time.strptime(meta["downloaded"], "%Y-%m-%d"))) / 86400
        if age < max_age_days:
            return meta["downloaded"]
    if os.path.exists(path) and not os.path.exists(meta_path) and not refresh:
        # a file put there by hand or an interrupted meta write: trust it for a week from its mtime
        if time.time() - os.path.getmtime(path) < max_age_days * 86400:
            today = time.strftime("%Y-%m-%d", time.localtime(os.path.getmtime(path)))
            json.dump({"downloaded": today, "size": os.path.getsize(path), "last_modified": None}, open(meta_path, "w"))
            return today
    log(f"downloading {url}")
    r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900)
    with open(path + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(path + ".part", path)
    today = time.strftime("%Y-%m-%d")
    json.dump({"downloaded": today, "size": os.path.getsize(path), "last_modified": r.headers.get("Last-Modified")}, open(meta_path, "w"))
    return today


def iter_objects(zip_path):
    """The companies of a register JSON dump one by one: the export is a pretty-printed array whose
    top-level objects open with '    {' and close with '    }' at four spaces of indentation."""
    z = zipfile.ZipFile(zip_path)
    name = next(n for n in z.namelist() if n.endswith(".json"))
    buf = []
    with z.open(name) as raw:
        for line in io.TextIOWrapper(raw, encoding="utf-8"):
            if line.startswith("    {") and not buf:
                buf = [line]
            elif buf:
                buf.append(line)
                if line.startswith("    }"):
                    text = "".join(buf).rstrip().rstrip(",")
                    buf = []
                    try:
                        yield json.loads(text)
                    except json.JSONDecodeError:
                        continue


def _date(d):
    m = re.match(r"(\d\d)\.(\d\d)\.(\d{4})", d or "")
    return f"{m.group(3)}-{m.group(2)}-{m.group(1)}" if m else None


def slim_general(obj):
    y = obj.get("yldandmed") or {}
    emtak = None
    for t in y.get("teatatud_tegevusalad") or []:
        if t.get("lopp_kpv"):
            continue
        if emtak is None or t.get("on_pohitegevusala"):
            emtak = {"code": t.get("emtak_kood"), "text": t.get("emtak_tekstina"), "nace": t.get("nace_kood"), "version": t.get("emtak_versioon") or 2}
    capital = None
    for k in y.get("kapitalid") or []:
        if not k.get("lopp_kpv"):
            try:
                capital = float(str(k.get("kapitali_suurus")).replace(",", "."))
            except (TypeError, ValueError):
                pass
    web = None
    for s in y.get("sidevahendid") or []:
        v = (s.get("sisu") or "").strip()
        if s.get("liik") == "WWW" and not s.get("lopp_kpv") and v and "@" not in v:   # some file an e-mail as their web address
            web = v
    reports = []
    for r in y.get("info_majandusaasta_aruannetest") or []:
        end = _date(r.get("majandusaasta_perioodi_lopp_kpv"))
        try:
            n = int(r.get("tootajate_arv"))
        except (TypeError, ValueError):
            n = None
        if end:
            reports.append([int(end[:4]), n, r.get("tegevusala_emtak_kood")])
    reports.sort(key=lambda r: r[0])
    return {"code": obj.get("ariregistri_kood"), "emtak": emtak, "capital": capital, "web": web, "reports": reports[-6:],
            "deleted": _date(y.get("kustutamise_kpv")), "founded": _date(y.get("esmaregistreerimise_kpv"))}


def slim_persons(obj):
    board, others = [], 0
    for p in obj.get("kaardile_kantud_isikud") or []:
        if p.get("lopp_kpv"):
            continue
        h = p.get("isikukood_hash") or p.get("isikukood_registrikood")
        if p.get("isiku_roll") in BOARD_ROLES:
            if h:
                board.append(str(h))
        else:
            others += 1
    return {"code": obj.get("ariregistri_kood"), "board": sorted(set(board)), "other_roles": others}


def slim_shareholders(obj):
    owners = []
    for p in obj.get("osanikud") or []:
        if p.get("lopp_kpv"):
            continue
        h = p.get("isikukood_hash") or p.get("isikukood_registrikood")
        if not h:
            continue
        try:
            stake = float(str(p.get("osaluse_protsent")).replace(",", "."))   # percent of the shares
        except (TypeError, ValueError):
            stake = None
        owners.append([str(h), stake])
    return {"code": obj.get("ariregistri_kood"), "owners": owners}


SLIMMERS = {GENERAL: slim_general, PERSONS: slim_persons, SHAREHOLDERS: slim_shareholders}


def slim_path(zip_path):
    return zip_path[:-len(".json.zip")] + ".slim.jsonl"


def ensure_slim(zip_path):
    """The slimmed companion of a register dump, written once per download (marked by the zip's mtime)."""
    out = slim_path(zip_path)
    if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(zip_path):
        return out
    fn = SLIMMERS[os.path.basename(zip_path)]
    t0 = time.time()
    n = 0
    with open(out + ".part", "w") as f:
        for obj in iter_objects(zip_path):
            f.write(json.dumps(fn(obj), ensure_ascii=False) + "\n")
            n += 1
    os.replace(out + ".part", out)
    log(f"slimmed {os.path.basename(zip_path)}: {n} companies in {time.time() - t0:.0f} s -> {os.path.basename(out)}")
    return out


def load_slim(path, codes):
    """Records of `codes` (ints) from a slim file."""
    want = {int(c) for c in codes}
    found = {}
    with open(path) as f:
        for line in f:
            i = line.find('"code": ')
            if i < 0:
                continue
            try:
                code = int(line[i + 8:line.find(",", i)])
            except ValueError:
                continue
            if code in want:
                found[code] = json.loads(line)
    return found


def load_tax(paths, codes):
    """Tax Board rows of `codes`: {code: [{year, q, taxes, labour, turnover, employees, sector_words}...]} sorted."""
    want = {str(c) for c in codes}
    rows = {}
    for p in paths:
        if not os.path.exists(p):
            continue
        with open(p, encoding="utf-8-sig", newline="") as f:
            rd = csv.DictReader(f)
            for r in rd:
                code = (r.get("Registrikood") or "").strip()
                if code not in want:
                    continue
                try:
                    year = int(r.get("Aasta"))
                except (TypeError, ValueError):
                    continue
                for q, roman in enumerate(["I", "II", "III", "IV"], start=1):
                    turnover = _num(r.get(f"Käive {roman} kv"))
                    employees = _num(r.get(f"Töötajate arv {roman} kv"))
                    taxes = _num(r.get(f"Riiklikud maksud {roman} kv"))
                    labour = _num(r.get(f"Tööjõumaksud {roman} kv"))
                    if turnover is None and employees is None and taxes is None:
                        continue
                    rows.setdefault(code, []).append({"year": year, "q": q, "taxes": taxes, "labour": labour, "turnover": turnover,
                                                      "employees": employees, "sector_words": r.get("Tegevusala") or ""})
    for code in rows:
        rows[code].sort(key=lambda x: (x["year"], x["q"]))
    return rows


def _num(s):
    s = (s or "").strip().replace(" ", "").replace(",", ".")
    if s == "":
        return None
    try:
        return int(float(s))
    except ValueError:
        return None


def health_of(status, quarters, report_overdue):
    """sound | watch | distressed from the register status, the tax quarters and the report deadline."""
    if status in ("N", "L"):
        return "distressed"
    recent = quarters[-4:]
    if len(recent) == 4 and all((q["taxes"] or 0) == 0 for q in recent) and any((q["employees"] or 0) > 0 for q in recent):
        return "distressed"
    if report_overdue:
        return "watch"
    years = {}
    for q in quarters:
        if q["turnover"] is not None:
            years.setdefault(q["year"], []).append(q["turnover"])
    full = sorted(y for y, qs in years.items() if len(qs) == 4)
    if len(full) >= 2:
        a, b = sum(years[full[-2]]), sum(years[full[-1]])
        if a > 0 and b < a * 0.6:
            return "watch"
    return "sound"


def enrich(tenants, root, max_age_days=7, refresh=False, today=None):
    """Add the register's and the Tax Board's facts to tenant rows (in place). Returns the source dates."""
    codes = [int(t["registry_code"]) for t in tenants if str(t.get("registry_code") or "").isdigit()]
    if not codes:
        return {}
    reg_dir = os.path.join(root, "data_raw", "ariregister")
    tax_dir = os.path.join(root, "data_raw", "emta")
    dates = {}
    slims = {}
    for name in (GENERAL, PERSONS, SHAREHOLDERS):
        path = os.path.join(reg_dir, name)
        try:
            dates[name] = download(REGISTER_BASE + name, path, max_age_days, refresh)
            slims[name] = load_slim(ensure_slim(path), codes)
        except Exception as e:  # noqa: BLE001 - each source is optional
            log(f"{name} unavailable ({e})")
            slims[name] = {}
    tax_paths = []
    for name, url in TAX_FILES.items():
        path = os.path.join(tax_dir, name)
        try:
            dates[name] = download(url, path, 30 if "varasemad" in name else max_age_days, refresh)
            tax_paths.append(path)
        except Exception as e:  # noqa: BLE001
            log(f"{name} unavailable ({e})")
    tax = load_tax(tax_paths, codes)
    today = today or time.strftime("%Y-%m-%d")
    year_now = int(today[:4])
    enriched = 0
    for t in tenants:
        try:
            code = int(t.get("registry_code"))
        except (TypeError, ValueError):
            continue
        g = slims[GENERAL].get(code) or {}
        p = slims[PERSONS].get(code) or {}
        s = slims[SHAREHOLDERS].get(code) or {}
        quarters = tax.get(str(code), [])
        emtak = g.get("emtak")
        sector = group(emtak["code"], emtak.get("version", 2)) if emtak else ""
        if not sector and quarters:
            sector = group_of_tax_words(quarters[-1]["sector_words"])
        reports = g.get("reports") or []
        last_q = quarters[-1] if quarters else None
        employees = last_q["employees"] if last_q and last_q["employees"] is not None else (reports[-1][1] if reports else None)
        recent = [q for q in quarters if q["turnover"] is not None][-4:]
        turnover = sum(q["turnover"] for q in recent) if recent else None
        taxes = sum((q["taxes"] or 0) + (q["labour"] or 0) for q in quarters[-4:]) if quarters else None
        # a report for the last closed year is due by 30 June; six months of grace before it counts
        due_year = year_now - 1 if today >= f"{year_now}-12-31" else year_now - 2
        report_overdue = bool(reports) and reports[-1][0] < due_year and (g.get("deleted") is None) and t.get("status") == "R"
        board = p.get("board") or []
        owners = [o[0] for o in (s.get("owners") or [])]
        t.update({
            "emtak": ({"code": emtak["code"], "text": emtak["text"], "nace": emtak.get("nace"), "section": sector} if emtak else None),
            "sector": sector or None,
            "capital": g.get("capital"),
            "web": g.get("web"),
            "employees": employees,
            "turnover": turnover,
            "taxes": taxes,
            "employees_hist": [[r[0], r[1]] for r in reports if r[1] is not None],
            "quarters": [[q["year"], q["q"], q["turnover"], q["employees"]] for q in quarters[-8:]],
            "board_size": len(board) if p else None,
            "shareholders": len(owners) if s else None,
            "owner_managed": (bool(set(board) & set(owners)) if p and s else None),
            "owners": sorted(set(board) | set(owners)),
            "deleted": g.get("deleted"),
            "report_overdue": report_overdue,
            "health": health_of(t.get("status"), quarters, report_overdue),
        })
        if g or p or s or quarters:
            enriched += 1
    log(f"enriched {enriched} of {len(tenants)} companies (register {len(slims[GENERAL])}, persons {len(slims[PERSONS])}, "
        f"shareholders {len(slims[SHAREHOLDERS])}, tax rows for {len(tax)})")
    return dates
