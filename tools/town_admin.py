#!/usr/bin/env python3
"""Administer a town (one SpacetimeDB database) from a site pack: derive its name, seed it, post an event, run SQL.

    python3 tools/town_admin.py name --site kvissentali
    python3 tools/town_admin.py seed --site kvissentali [--server http://127.0.0.1:3300] [--db <name>] [--debug]
    python3 tools/town_admin.py post-event --db <name> --kind news --title "..." --source ERR --link https://... [--tunnus ..] [--published ..]
    python3 tools/town_admin.py sql --db <name> "SELECT COUNT(*) FROM parcel"

The town name is `vk-t<E>-<N>-<hash8>` from the tile centre, where hash8 is the first 8 hex digits of
sha256(parcels.json bytes ++ tenants.json bytes); the game computes the same (Sites.pack_hash) and the module
refuses players whose pack differs. Seeding calls the module's admin reducers one row at a time over the HTTP API
(`POST /v1/database/<db>/call/<reducer>`, JSON array body) with the publisher's token: `SPACETIME_TOKEN` in the
environment, else `spacetime login show --token`. Economy parameters come from assets/data/economy.json.
"""
import argparse, hashlib, json, os, subprocess, sys, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SERVER = "http://127.0.0.1:3300"
ECONOMY = os.path.join(ROOT, "assets", "data", "economy.json")
UNSELLABLE_OWNERSHIP = ("Riigiomand", "Munitsipaalomand")
UNSELLABLE_PURPOSE = ("TRANSPORDIMAA", "VEEKOGUDE_MAA", "KAITSEALUNE_MAA", "RIIGIKAITSEMAA")


def log(msg):
    print(f"[town] {msg}", flush=True)


def pack_hash(site_dir):
    h = hashlib.sha256()
    for name in ("parcels.json", "tenants.json"):
        p = os.path.join(site_dir, name)
        if os.path.exists(p):
            h.update(open(p, "rb").read())
    return h.hexdigest()[:8]


def town_name(site, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    cx, cy = m["terrain"]["center"]
    return f"vk-t{int(cx)}-{int(cy)}-{pack_hash(site_dir)}"


def token():
    t = os.environ.get("SPACETIME_TOKEN")
    if t:
        return t.strip()
    try:
        out = subprocess.run(["spacetime", "login", "show", "--token"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        sys.exit(f"[town] no SPACETIME_TOKEN and `spacetime login show --token` failed: {e}")
    import re
    m = re.search(r"eyJ[\w-]+\.[\w-]+\.[\w-]+", out)
    if not m:
        sys.exit("[town] could not find a JWT in `spacetime login show --token` output")
    return m.group(0)


class Client:
    def __init__(self, server, db, tok):
        self.base = server.rstrip("/") + "/v1/database/" + db
        self.headers = {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}

    def call(self, reducer, *args):
        req = urllib.request.Request(self.base + "/call/" + reducer, data=json.dumps(list(args)).encode(), headers=self.headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode()
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            raise RuntimeError(f"{reducer}: HTTP {e.code} {body[:300]}") from None

    def sql(self, query):
        req = urllib.request.Request(self.base + "/sql", data=query.encode(), headers={"Authorization": self.headers["Authorization"]}, method="POST")
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode())

    def exists(self):
        try:
            urllib.request.urlopen(urllib.request.Request(self.base + "/identity"), timeout=10)
            return True
        except urllib.error.HTTPError:
            return False


def economy():
    if os.path.exists(ECONOMY):
        return json.load(open(ECONOMY))
    return {"starting_cash": 250000, "seconds_per_month": 600, "tax_rate_year": 0.005, "yield_by_purpose": {"default": 0.01},
            "arrears_chance": {"R": 0.03, "default": 0.12}, "drift": 0.01, "ai_bid_chance": 0.2, "families": ["Kask", "Tamm", "Lepik"],
            "grace_months": 3, "penalty": 0.1}


def permille(x):
    return int(round(float(x) * 1000))


def rent_month(land_value, purpose, eco):
    y = eco.get("yield_by_purpose", {})
    rate = y.get(purpose, y.get("default", 0.01))
    r = int(land_value * rate / 12)
    return max(r, 1) if land_value and rate else 0


def seed(site, server, db, debug, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    db = db or town_name(site, root)
    c = Client(server, db, token())
    if not c.exists():
        sys.exit(f"[town] database {db} not found on {server}: publish it first (make town SITE={site})")
    eco = economy()
    pd = json.load(open(os.path.join(site_dir, "parcels.json")))
    m = json.load(open(os.path.join(site_dir, "site.json")))
    cx, cy = m["terrain"]["center"]
    c.call("seed_config", f"t{int(cx)}_{int(cy)}", pack_hash(site_dir), int(eco.get("seconds_per_month", 600)), bool(debug), int(eco.get("starting_cash", 250000)),
           permille(eco.get("tax_rate_year", 0.005)), permille(eco.get("arrears_chance", {}).get("R", 0.03)), permille(eco.get("arrears_chance", {}).get("default", 0.12)),
           permille(eco.get("drift", 0.01)), permille(eco.get("ai_bid_chance", 0.2)), int(eco.get("grace_months", 3)), permille(eco.get("penalty", 0.1)),
           ",".join(eco.get("families", [])))
    n = 0
    for u in pd["parcels"]:
        lv = int(u.get("land_value") or 0)
        purpose = (u.get("purpose") or ["SIHTOTSTARBETA_MAA"])[0]
        sellable = lv > 0 and u.get("ownership") not in UNSELLABLE_OWNERSHIP and purpose not in UNSELLABLE_PURPOSE
        c.call("seed_parcel", u["tunnus"], u.get("address") or "", purpose, int(u.get("area") or 0), lv, rent_month(lv, purpose, eco),
               u.get("ownership") or "", sellable, float(u.get("x", 0)), float(u.get("z", 0)))
        n += 1
    log(f"{n} parcels seeded")
    tpath = os.path.join(site_dir, "tenants.json")
    nt = 0
    if os.path.exists(tpath):
        by_tunnus = {}
        for t in json.load(open(tpath))["tenants"]:
            if t.get("tunnus") and t.get("match") == "exact":
                by_tunnus.setdefault(t["tunnus"], []).append(t)
        for tunnus, ts in by_tunnus.items():
            c.call("clear_tenants", tunnus)
            for t in ts:
                c.call("seed_tenant", tunnus, t["name"], str(t["registry_code"]), t.get("legal_form") or "", t.get("status") or "", t.get("since") or "")
                nt += 1
    log(f"{nt} tenants seeded")
    ns = 0
    sdir = os.path.join(site_dir, "data", "structures")
    if os.path.isdir(sdir):
        sys.path.insert(0, os.path.join(root, "tools"))
        from validate_site import read_tres  # noqa: E402
        for f in sorted(os.listdir(sdir)):
            if not f.endswith(".tres"):
                continue
            s = read_tres(os.path.join(sdir, f))
            if not s.get("id"):
                continue
            purposes = s.get("purposes") or []
            c.call("seed_structure", s["id"], int(s.get("cost_money") or 0), int(s.get("rent_bonus") or 0), s.get("requires") or "",
                   ",".join(purposes) if isinstance(purposes, list) else str(purposes))
            ns += 1
    log(f"{ns} structures seeded")
    c.call("finish_seed")
    log(f"{db} ready on {server}")
    return db


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("name"); p.add_argument("--site", default="kvissentali"); p.add_argument("--root", default=ROOT)
    p = sub.add_parser("seed"); p.add_argument("--site", default="kvissentali"); p.add_argument("--root", default=ROOT)
    p.add_argument("--server", default=DEFAULT_SERVER); p.add_argument("--db", default=None); p.add_argument("--debug", action="store_true")
    p = sub.add_parser("post-event"); p.add_argument("--server", default=DEFAULT_SERVER); p.add_argument("--db", required=True)
    for k in ("kind", "title", "source", "link"):
        p.add_argument("--" + k, required=True)
    p.add_argument("--tunnus", default=""); p.add_argument("--published", default="")
    p = sub.add_parser("sql"); p.add_argument("--server", default=DEFAULT_SERVER); p.add_argument("--db", required=True); p.add_argument("query")
    a = ap.parse_args()
    if a.cmd == "name":
        print(town_name(a.site, a.root))
    elif a.cmd == "seed":
        seed(a.site, a.server, a.db, a.debug, a.root)
    elif a.cmd == "post-event":
        Client(a.server, a.db, token()).call("post_event", a.kind, a.title, a.source, a.link, a.tunnus, a.published)
        log("posted")
    elif a.cmd == "sql":
        print(json.dumps(Client(a.server, a.db, token()).sql(a.query), ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
