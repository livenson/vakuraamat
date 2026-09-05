#!/usr/bin/env python3
"""Developer channel into a running Vakuraamat (debug builds): reports out, commands in.

    python3 tools/dev.py watch                      # tail the report feed (what the player sent with F8)
    python3 tools/dev.py reports [n]                # list the latest reports
    python3 tools/dev.py show <report.json|id>      # print one report (without the long lists)
    python3 tools/dev.py replay <report.json|id>    # relaunch the world at the report's spot
    python3 tools/dev.py reload <path> [<path>...]  # hot reload scripts / era scenes / pack data / shaders
    python3 tools/dev.py restart                    # the game saves a report and relaunches itself there
    python3 tools/dev.py quit
    python3 tools/dev.py codes                      # toggle the K codes overlay
    python3 tools/dev.py teleport <x> <z> [yaw_deg]
    python3 tools/dev.py era <era_id>
    python3 tools/dev.py screenshot </abs/path.png>
    python3 tools/dev.py results                    # tail the command results log
    python3 tools/dev.py instances                  # running games (pid, site); commands go to the newest,
                                                    # or use --pid <n> / --all before the command

Commands are JSON lines appended to <userdir>/dev/commands.jsonl, read by the DevChannel autoload
twice a second; results land in <userdir>/dev/results.log. Reports live in <userdir>/reports/.
"""
import json, os, platform, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot" if platform.system() == "Darwin" else "godot")


def user_dir():
    if platform.system() == "Darwin":
        return os.path.expanduser("~/Library/Application Support/Godot/app_userdata/Vakuraamat")
    if platform.system() == "Windows":
        return os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Vakuraamat")
    return os.path.expanduser("~/.local/share/godot/app_userdata/Vakuraamat")


def instances():
    """Running games: [{pid, started, site, args}] newest first (stale entries of dead pids are dropped)."""
    d = os.path.join(user_dir(), "dev", "instances")
    out = []
    if not os.path.isdir(d):
        return out
    for f in os.listdir(d):
        if not f.endswith(".json"):
            continue
        try:
            info = json.load(open(os.path.join(d, f)))
            os.kill(int(info["pid"]), 0)
            out.append(info)
        except (ProcessLookupError, PermissionError, ValueError, KeyError, json.JSONDecodeError):
            try:
                os.remove(os.path.join(d, f))
            except OSError:
                pass
    return sorted(out, key=lambda i: i.get("started", ""), reverse=True)


TARGET = {"pid": None, "all": False}


def send(cmd):
    d = os.path.join(user_dir(), "dev")
    os.makedirs(d, exist_ok=True)
    if TARGET["all"]:
        cmd["pid"] = 0
    elif TARGET["pid"]:
        cmd["pid"] = TARGET["pid"]
    else:
        inst = instances()
        if not inst:
            print("no running game registered under dev/instances; sending to whichever starts next"); cmd["pid"] = 0
        else:
            cmd["pid"] = inst[0]["pid"]
            if len(inst) > 1:
                print(f"{len(inst)} games running; targeting the newest, pid {inst[0]['pid']} ({inst[0].get('site')}). Use --pid or --all.")
    with open(os.path.join(d, "commands.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(cmd, ensure_ascii=False) + "\n")
    print("sent", json.dumps(cmd, ensure_ascii=False))


def res_path(p):
    if p.startswith(("res://", "user://")):
        return p
    p = os.path.relpath(os.path.abspath(p), ROOT) if os.path.isabs(p) else p
    return "res://" + p.replace(os.sep, "/").lstrip("./")


def tail(path, lines=20, follow=True):
    if not os.path.exists(path):
        print(f"(no {path} yet)")
        if not follow:
            return
        while not os.path.exists(path):
            time.sleep(0.5)
    subprocess.call(["tail", "-n", str(lines)] + (["-f"] if follow else []) + [path])


def report_path(arg):
    if os.path.exists(arg):
        return arg
    p = os.path.join(user_dir(), "reports", arg if arg.endswith(".json") else arg + ".json")
    return p if os.path.exists(p) else None


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__); return 0
    while argv and argv[0] in ("--all", "--pid"):
        if argv[0] == "--all":
            TARGET["all"] = True; argv = argv[1:]
        else:
            TARGET["pid"] = int(argv[1]); argv = argv[2:]
    cmd, args = argv[0], argv[1:]
    if cmd == "instances":
        for i in instances():
            print(f"pid {i['pid']}  since {i.get('started')}  site {i.get('site')}  {' '.join(i.get('args', []))}")
        return 0
    rdir = os.path.join(user_dir(), "reports")
    if cmd == "watch":
        tail(os.path.join(rdir, "feed.log"))
    elif cmd == "results":
        tail(os.path.join(user_dir(), "dev", "results.log"))
    elif cmd == "reports":
        n = int(args[0]) if args else 10
        files = sorted(f for f in os.listdir(rdir) if f.endswith(".json")) if os.path.isdir(rdir) else []
        for f in files[-n:]:
            r = json.load(open(os.path.join(rdir, f), encoding="utf-8"))
            print(f"{r.get('id')}  {r.get('site')}/{r.get('era')}  at {r.get('position')}  {r.get('target', {}).get('label', '-')}  | {r.get('note', '')[:80]}")
    elif cmd == "show":
        p = report_path(args[0])
        if not p:
            print("no such report"); return 1
        r = json.load(open(p, encoding="utf-8"))
        for k in ("id", "time", "note", "site", "era", "chapter", "position", "yaw_deg", "pitch_deg", "target", "buildings_nearby", "errors", "screenshot", "save_slot", "replay"):
            v = r.get(k)
            if v not in (None, [], {}, ""):
                print(f"{k}: {json.dumps(v, ensure_ascii=False, indent=1) if isinstance(v, (dict, list)) else v}")
        print("nearby:", ", ".join(f"{n.get('label') or n.get('name')} ({n.get('distance')} m)" for n in r.get("nearby", [])))
    elif cmd == "replay":
        p = report_path(args[0])
        if not p:
            print("no such report"); return 1
        os.execvp(GODOT, [GODOT, "--path", ROOT, "res://scenes/world/world.tscn", "--", "--report=" + os.path.abspath(p), "--windowed"])
    elif cmd == "reload":
        send({"reload": [res_path(p) for p in args]})
    elif cmd == "restart":
        send({"restart": True})
    elif cmd == "quit":
        send({"quit": True})
    elif cmd == "codes":
        send({"codes": True})
    elif cmd == "teleport":
        send({"teleport": [float(a) for a in args]})
    elif cmd == "era":
        send({"era": args[0]})
    elif cmd == "screenshot":
        send({"screenshot": os.path.abspath(args[0])})
    elif cmd == "note":
        send({"note": " ".join(args)})
    else:
        print(__doc__); return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
