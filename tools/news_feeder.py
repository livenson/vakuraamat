#!/usr/bin/env python3
"""News feeder: real regional headlines and official notices for a town, pushed into the town's SpacetimeDB
database through the `post_event` reducer (modules cannot fetch HTTP themselves), or written to a local
news.json for offline play.

    python3 tools/news_feeder.py --site kvissentali [--db <town>] [--server http://127.0.0.1:3300]
                                 [--once | --loop 900] [--dry-run] [--local [--out <path>]] [--no-notices] [--no-rss]
                                 [--max-per-run 40] [--root <workspace>]

Sources: ERR (`www.err.ee/rss`, items tagged Eesti), Tartu Postimees and Lõuna-Eesti Postimees RSS for Tartu
county packs; Official Announcements XML (`ametlikudteadaanded.ee/ee/-/<type>/xml`) for planning procedures
and auctions whose address inputs name the pack's settlement or municipality. Stored per item: composed or
original title, source, link, date, area. Never stored: article text, notice bodies, publishers, addressees
or any person's name. Town config comes from parcels.json's `summary` (county, settlements, municipalities)
and can be overridden by sites/<id>/news_config.json {"feeds": [...], "names": [...], "notice_types": [...]}.
State (seen ids) lives in data_raw/news/<town>.json.
"""
import argparse, hashlib, json, os, re, subprocess, sys, time, urllib.error, urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pipeline"))
import paths  # noqa: E402
ROOT = paths.ROOT   # the bundle directory when frozen into the tile-service sidecar
UA = {"User-Agent": "vakuraamat-news/0.1 (open-source game; headlines and links only)"}
DEFAULT_SERVER = "http://127.0.0.1:3300"
ERR = {"id": "err", "name": "ERR", "url": "https://www.err.ee/rss", "category": "Eesti", "area": "country", "terms": "ERR: RSS free to embed"}
TARTU_PM = {"id": "tartu_pm", "name": "Tartu Postimees", "url": "https://tartu.postimees.ee/rss", "area": "county", "terms": "headlines and links only"}
LOUNA_PM = {"id": "louna_pm", "name": "Lõuna-Eesti Postimees", "url": "https://lounapostimees.postimees.ee/rss", "area": "county", "terms": "headlines and links only"}
FEEDS_BY_COUNTY = {"Tartu maakond": [TARTU_PM, LOUNA_PM, ERR], "Valga maakond": [LOUNA_PM, ERR], "Võru maakond": [LOUNA_PM, ERR], "Põlva maakond": [LOUNA_PM, ERR]}
DEFAULT_FEEDS = [ERR]
NOTICE_ALLOWED = ("planeeringud", "riigivara", "pankrotimenetlus")   # planning; state property; bankruptcy proceedings
COMPANY_NOTICES = ("pankrotimenetlus",)   # local only when the notice names one of the tile's companies (registry code or name)
NOTICE_URL = "https://www.ametlikudteadaanded.ee/ee/-/{kind}/xml"
NS = "{http://www.ametlikudteadaanded.ee/xsd/2014-06-01/teadaanne.xsd}"


def log(msg):
    print(f"[news] {msg}", flush=True)


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(); self.parts = []

    def handle_data(self, d):
        self.parts.append(d)


def strip_html(s):
    p = _Text(); p.feed(s or ""); return re.sub(r"\s+", " ", " ".join(p.parts)).strip()


def town_config(site, root):
    site_dir = os.path.join(root, "sites", site)
    pd = json.load(open(os.path.join(site_dir, "parcels.json")))
    s = pd.get("summary") or {}
    names = sorted(set((s.get("settlements") or []) + (s.get("municipalities") or [])))
    cfg = {"town": site, "county": s.get("county"), "names": names, "feeds": FEEDS_BY_COUNTY.get(s.get("county"), DEFAULT_FEEDS), "notice_types": list(NOTICE_ALLOWED)}
    company_index.path = os.path.join(root, "sites", site, "tenants.json")
    ov = os.path.join(site_dir, "news_config.json")
    if os.path.exists(ov):
        cfg.update(json.load(open(ov)))
    cfg["notice_types"] = [k for k in cfg["notice_types"] if k in NOTICE_ALLOWED]
    return cfg


def get(url, timeout=30):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout).read()


def iso(d):
    try:
        return parsedate_to_datetime(d).isoformat()
    except (TypeError, ValueError):
        return d or ""


def fetch_rss(feed, names):
    out = []
    root = ET.fromstring(get(feed["url"]))
    for item in root.iter("item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        if not title or not link:
            continue
        cats = [c.text.strip() for c in item.findall("category") if c.text]
        if feed.get("category") and feed["category"] not in cats:
            continue
        guid = (item.findtext("guid") or link).strip()
        area = "local" if any(n.lower().split(" ")[0] in title.lower() for n in names) else feed.get("area", "country")
        out.append({"id": "rss:" + hashlib.sha1(guid.encode()).hexdigest()[:16], "kind": "news", "source": feed["name"], "title": title, "url": link,
                    "published": iso(item.findtext("pubDate")), "area": area, "tunnus": ""})
    return out


def location_keys(parcels, names):
    """Street and farm name stems of the tile plus its settlement names: a notice mentioning one is local."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "pipeline"))
    from fetch_tenants import address_keys  # noqa: E402
    stems = set()
    for u in parcels:
        for stem, _num, _sub in address_keys(u.get("address")):
            if len(stem) > 3:
                stems.add(stem)
    settlements = {n.lower() for n in names if not n.lower().endswith(" linn") and not n.lower().endswith(" vald")}
    return stems, settlements


def company_index(parcels):
    """The tile's companies (sites/<id>/tenants.json beside parcels.json): registry codes and lower-case
    names, each pointing at the company's parcel, so a bankruptcy or liquidation notice finds its plot."""
    out = {"codes": {}, "names": {}}
    if not parcels:
        return out
    tpath = getattr(company_index, "path", None)
    if not tpath or not os.path.exists(tpath):
        return out
    for t in json.load(open(tpath)).get("tenants", []):
        if t.get("match") != "exact" or not t.get("tunnus"):
            continue
        code = str(t.get("registry_code") or "")
        if code.isdigit():
            out["codes"][code] = t["tunnus"]
        name = (t.get("name") or "").lower().strip()
        if len(name) > 6:
            out["names"][name] = t["tunnus"]
    return out


def fetch_notices(kind, names, parcels, municipality_cap=5):
    """Planning notices (`planeeringud`) and state property sales (`riigivara`). Location is free text, so a
    notice is local when an input names one of the tile's streets, farms or settlements; municipal notices
    (publisher is the pack's municipality) are kept up to `municipality_cap` per run as county news."""
    out, municipal = [], []
    root = ET.fromstring(get(NOTICE_URL.format(kind=kind), timeout=180))
    stems, settlements = location_keys(parcels, names)
    munis = {n.lower().split(" ")[0] for n in names if n.lower().endswith((" linn", " vald"))}
    full_names = {n.lower() for n in names}
    tunnus_set = {u["tunnus"] for u in parcels if u.get("tunnus")}
    addr_index = {u["address"].lower(): u["tunnus"] for u in parcels if u.get("address") and len(u["address"]) > 5}
    companies = company_index(parcels)
    for t in root.iter(NS + "teadaanne"):
        number = t.findtext("teate_number") or ""
        url = t.findtext("url") or ""
        kind_name = re.sub(r"\s*\(.*?\)\s*$", "", t.findtext("mall/nimi") or t.findtext("liik/nimi") or kind)
        if kind == "riigivara" and not re.search(r"enampakk|müü|rendi", kind_name, re.I):
            continue
        publisher = (t.findtext("andmeandja/nimi") or "").lower()
        published = t.findtext("avaldamise_kpv") or ""
        texts = []
        for row in t.iter("sisendirida"):
            v = strip_html(row.findtext("vaartus") or "")
            if v:
                texts.append((row.findtext("nimi") or "", v))
        blob = " ".join(v for _n, v in texts).lower()
        key_hit = next((k for k in sorted(stems | settlements, key=len, reverse=True) if re.search(r"\b" + re.escape(k) + r"\b", blob)), "")
        municipal_hit = any(m in publisher for m in munis) or any(re.search(r"\b" + m + r"\b", blob) for m in munis)
        # street names repeat across Estonia: local needs the tile's street or settlement AND the pack's municipality;
        # state property notices list many places, so they need a full settlement name or one of the tile's cadastral numbers
        tunnus_hit = next((tn for tn in tunnus_set if tn in blob), "")
        company_hit = next((tn for code, tn in companies["codes"].items() if re.search(r"\b" + code + r"\b", blob)), "")
        if not company_hit:
            company_hit = next((tn for name, tn in companies["names"].items() if name in blob), "")
        if company_hit:
            tunnus_hit = tunnus_hit or company_hit
        if kind in COMPANY_NOTICES:
            local = company_hit != ""
        elif kind == "riigivara":
            local = tunnus_hit != "" or (key_hit != "" and any(f in blob for f in full_names))
        else:
            local = key_hit != "" and municipal_hit
        if not local and not any(m in publisher for m in munis):
            continue
        where = ""
        for _n, v in texts:
            if key_hit and key_hit in v.lower():
                for sentence in re.split(r"(?<=[.;])\s+", v):
                    if key_hit in sentence.lower():
                        where = sentence
                        break
                break
        if not where:
            for n, v in texts:
                if re.search(r"asukoht|andmed|teatab|eesmark", n, re.I):
                    where = re.split(r"(?<=[.;])\s+", v, 1)[0]
                    break
        if not where and texts:
            where = re.split(r"(?<=[.;])\s+", texts[0][1], 1)[0]
        where = re.sub(r"^[\s,;:.]*(et\s+)?", "", where)[:140].strip()
        where = where[:1].upper() + where[1:]
        tunnus = tunnus_hit
        if not tunnus:
            for a, tn in addr_index.items():
                if re.search(r"\b" + re.escape(a) + r"\b", blob):
                    tunnus = tn
                    break
        ev = {"id": "at:" + number, "kind": "official", "source": "Ametlikud Teadaanded", "title": f"{kind_name}: {where}"[:200], "url": url,
              "published": published, "area": "local" if local else "county", "tunnus": tunnus}
        (out if local else municipal).append(ev)
    return out + municipal[:municipality_cap]


def state_path(root, town):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "pipeline"))
    import paths
    d = paths.raw("news")
    return os.path.join(d, f"{town}.json")


def load_state(path):
    return json.load(open(path)) if os.path.exists(path) else {"seen": {}, "posted": 0}


def token():
    t = os.environ.get("SPACETIME_TOKEN")
    if t:
        return t.strip()
    out = subprocess.run(["spacetime", "login", "show", "--token"], capture_output=True, text=True).stdout
    m = re.search(r"eyJ[\w-]+\.[\w-]+\.[\w-]+", out)
    if not m:
        sys.exit("[news] no SPACETIME_TOKEN and no token from `spacetime login show --token`")
    return m.group(0)


def post(server, db, tok, e):
    body = json.dumps([e["kind"], e["title"], e["source"], e["url"], e["tunnus"], e["published"]]).encode()
    req = urllib.request.Request(f"{server.rstrip('/')}/v1/database/{db}/call/post_event", data=body,
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"}, method="POST")
    urllib.request.urlopen(req, timeout=30).read()


def run(a):
    cfg = town_config(a.site, a.root)
    parcels = json.load(open(os.path.join(a.root, "sites", a.site, "parcels.json"))).get("parcels", [])
    events = []
    if not a.no_rss:
        for f in cfg["feeds"]:
            try:
                events += fetch_rss(f, cfg["names"])
            except Exception as e:  # noqa: BLE001 - one dead feed must not stop the run
                log(f"{f['name']} unavailable ({e})")
    if not a.no_notices:
        for kind in cfg["notice_types"]:
            try:
                events += fetch_notices(kind, cfg["names"], parcels)
            except Exception as e:  # noqa: BLE001
                log(f"notices {kind} unavailable ({e})")
    events.sort(key=lambda e: e["published"], reverse=True)
    town = a.db or a.site
    sp = state_path(a.root, town)
    st = load_state(sp)
    fresh = [e for e in events if e["id"] not in st["seen"]][: a.max_per_run]
    log(f"{cfg['town']} ({cfg['county']}): {len(events)} items from {len(cfg['feeds'])} feeds + {len(cfg['notice_types'])} notice types, {len(fresh)} new")
    if a.dry_run:
        for e in fresh:
            print(f"  {e['kind']:8} {e['published'][:10]:10} {e['source']:22} {e['title'][:90]}  {e['url']}")
        return
    if a.local:
        out_path = a.out or os.path.join(a.root, "sites", a.site, "news.json")
        d = json.load(open(out_path)) if os.path.exists(out_path) else {"events": []}
        d["attribution"] = sorted({f.get("terms", "") for f in cfg["feeds"]} | {"Ametlikud Teadaanded (metadata only)"})
        d["town"] = a.site
        d["fetched"] = time.strftime("%Y-%m-%d")
        known = {e["id"] for e in d["events"]}
        d["events"] = ([e for e in fresh if e["id"] not in known] + d["events"])[:200]
        json.dump(d, open(out_path, "w"), ensure_ascii=False, indent=0)
        log(f"wrote {out_path}: {len(d['events'])} events")
    else:
        tok = token()
        n = 0
        for e in fresh:
            try:
                post(a.server, town, tok, e)
                n += 1
            except urllib.error.HTTPError as err:
                body = err.read().decode(errors="replace")[:200]
                if err.code == 404:
                    sys.exit(f"[news] reducer post_event not found on {town}: publish the module first ({body})")
                log(f"post failed {err.code}: {body}")
                continue
        st["posted"] = st.get("posted", 0) + n
        log(f"posted {n} events to {town}")
    for e in fresh:
        st["seen"][e["id"]] = e["published"]
    cutoff = time.strftime("%Y-%m-%d", time.gmtime(time.time() - 60 * 86400))
    st["seen"] = {k: v for k, v in st["seen"].items() if not v or v[:10] >= cutoff}
    st["last_run"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    json.dump(st, open(sp, "w"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="kvissentali")
    ap.add_argument("--db", default=None, help="town database name (default: tools/town_admin.py name)")
    ap.add_argument("--server", default=DEFAULT_SERVER)
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--loop", type=int, default=0, help="seconds between runs")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--local", action="store_true", help="write sites/<id>/news.json instead of posting")
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-notices", action="store_true")
    ap.add_argument("--no-rss", action="store_true")
    ap.add_argument("--max-per-run", type=int, default=40)
    a = ap.parse_args(argv)
    if a.db is None and not a.local and not a.dry_run:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from town_admin import town_name  # noqa: E402
        a.db = town_name(a.site, a.root)
    while True:
        run(a)
        if not a.loop:
            break
        time.sleep(a.loop)


if __name__ == "__main__":
    main()
