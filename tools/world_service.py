#!/usr/bin/env python3
"""World service: share a generated world by code, visit a friend's, and carry deliveries back.

    python3 tools/world_service.py [--port 8766] [--store data_raw/worlds]

A world is a small descriptor, not a save: where it is (centre, size, eras), how its story was
composed (seed, blocks) and which consequence flags its owner has committed. A visitor's game
regenerates the same pack from that through its own tile service. Deliveries are consequence flags
a visitor set inside the friend's world; the owner's game pulls them and applies them.

    POST /worlds                 {name, site_id, generated, center, size, eras, seed, blocks, flags, owner}
                                 -> {code}
    GET  /worlds/<code>          -> descriptor
    PUT  /worlds/<code>/flags    {flags}  (owner republishes their committed flags)
    POST /worlds/<code>/deliveries  {flag, by, era}  -> {n}
    GET  /worlds/<code>/deliveries?since=<n>  -> {deliveries: [{n, flag, by, era, at}]}
Loopback by default; plain JSON files under --store. No accounts: the code is the key.
"""
import argparse, json, os, random, re, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "data_raw", "worlds")
LOCK = threading.Lock()
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O/1/I


def log(msg):
    print(f"[world_service] {msg}", flush=True)


def path_for(code):
    return os.path.join(STORE, code + ".json")


def load_world(code):
    if not re.fullmatch(r"[A-Z0-9]{6}", code or ""):
        return None
    p = path_for(code)
    return json.load(open(p)) if os.path.exists(p) else None


def save_world(w):
    tmp = path_for(w["code"]) + ".tmp"
    json.dump(w, open(tmp, "w"), indent=1)
    os.replace(tmp, path_for(w["code"]))


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", "0"))
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            return None

    def log_message(self, fmt, *args):
        log(fmt % args)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        parts = [p for p in u.path.split("/") if p]
        if parts == ["health"]:
            return self._json(200, {"ok": True, "version": 1})
        if len(parts) >= 2 and parts[0] == "worlds":
            with LOCK:
                w = load_world(parts[1])
            if not w:
                return self._json(404, {"error": "no such world"})
            if len(parts) == 2:
                pub = {k: v for k, v in w.items() if k != "deliveries"}
                pub["deliveries_count"] = len(w.get("deliveries", []))
                return self._json(200, pub)
            if parts[2] == "deliveries":
                since = int(urllib.parse.parse_qs(u.query).get("since", ["0"])[0])
                return self._json(200, {"deliveries": [d for d in w.get("deliveries", []) if d["n"] > since]})
        return self._json(404, {"error": "no such route"})

    def do_POST(self):
        parts = [p for p in urllib.parse.urlparse(self.path).path.split("/") if p]
        req = self._body()
        if req is None:
            return self._json(400, {"error": "bad json"})
        if parts == ["worlds"]:
            for k in ("name", "site_id"):
                if k not in req:
                    return self._json(400, {"error": f"{k} missing"})
            with LOCK:
                code = "".join(random.choice(ALPHABET) for _ in range(6))
                while os.path.exists(path_for(code)):
                    code = "".join(random.choice(ALPHABET) for _ in range(6))
                w = {"code": code, "name": str(req["name"])[:60], "site_id": str(req["site_id"])[:60], "generated": bool(req.get("generated", True)),
                     "center": req.get("center"), "size": int(req.get("size") or 1024), "eras": str(req.get("eras") or "1798,1938,2026"),
                     "seed": req.get("seed"), "blocks": req.get("blocks"), "flags": dict(req.get("flags") or {}), "owner": str(req.get("owner", ""))[:40],
                     "created": time.strftime("%Y-%m-%dT%H:%M:%S"), "deliveries": []}
                save_world(w)
            log(f"published {code} ({w['name']}, {w['site_id']})")
            return self._json(201, {"code": code})
        if len(parts) == 3 and parts[0] == "worlds" and parts[2] == "deliveries":
            if not req.get("flag"):
                return self._json(400, {"error": "flag missing"})
            with LOCK:
                w = load_world(parts[1])
                if not w:
                    return self._json(404, {"error": "no such world"})
                n = len(w["deliveries"]) + 1
                w["deliveries"].append({"n": n, "flag": str(req["flag"])[:64], "by": str(req.get("by", ""))[:40], "era": str(req.get("era", ""))[:32], "at": time.strftime("%Y-%m-%dT%H:%M:%S")})
                w["flags"][str(req["flag"])[:64]] = True
                save_world(w)
            log(f"{parts[1]}: delivery {req['flag']} by {req.get('by', '?')}")
            return self._json(201, {"n": n})
        return self._json(404, {"error": "no such route"})

    def do_PUT(self):
        parts = [p for p in urllib.parse.urlparse(self.path).path.split("/") if p]
        req = self._body()
        if len(parts) == 3 and parts[0] == "worlds" and parts[2] == "flags" and req is not None:
            with LOCK:
                w = load_world(parts[1])
                if not w:
                    return self._json(404, {"error": "no such world"})
                w["flags"].update({str(k): bool(v) for k, v in (req.get("flags") or {}).items()})
                save_world(w)
            return self._json(200, {"ok": True})
        return self._json(404, {"error": "no such route"})


def main():
    global STORE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8766)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--store", default=STORE)
    a = ap.parse_args()
    STORE = a.store
    os.makedirs(STORE, exist_ok=True)
    open(os.path.join(STORE, ".gdignore"), "a").close()
    srv = ThreadingHTTPServer((a.bind, a.port), Handler)
    log(f"listening on http://{a.bind}:{a.port}  store {STORE}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
