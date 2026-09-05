#!/usr/bin/env python3
"""Composes a site's story from quest blocks (blocks/*.json).

Used by tools/new_site.py (and so by the tile service). Given the eras, the layout anchors and a
seed, it picks blocks, assigns each block's roles to eras, names one NPC per era, and returns
everything the pack needs: artifact items, consequence points, scene nodes per era, ink knots per
era, strings, objectives, ending rules and journal locations. Deterministic for a given seed.

    python3 tools/compose_story.py --list                 # blocks available
    python3 tools/compose_story.py --eras 1798,1938,2026 --seed 7 --dry-run
"""
import argparse, json, os, random, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOCKS_DIR = os.path.join(ROOT, "blocks")

NAMES = [
    (1850, ["Peep", "Jüri", "Tõnis", "Andres", "Liisu", "Kai", "Els", "Madli"]),
    (1950, ["August", "Oskar", "Helmi", "Salme", "Linda", "Arnold", "Elmar", "Hilda"]),
    (9999, ["Kadri", "Kristjan", "Tõnu", "Liis", "Marek", "Ene", "Priit", "Reet"]),
]
INTROS = {
    "oldest": [
        ["Sa ei ole saksa. Sa ei ole ka meie oma. Mis sa siis oled? # en: You're not a German. You're not one of us either. What are you, then?",
         "Ütle, kui välja mõtled. Mul on töö pooleli. # en: Tell me when you've worked it out. I've work half done."],
        ["Võõras. {PLACE} ei näe võõraid tihti. # en: A stranger. {PLACE} does not see strangers often.",
         "Räägi, aga lühidalt. Päev on lühike. # en: Speak, but briefly. The day is short."],
    ],
    "middle": [
        ["Sa oled see, kellest räägitakse. Käid ringi ja küsid. # en: You're the one they talk about. Walking around, asking.",
         "Küsi siis. Aasta on {YEAR} ja aega on. # en: Ask, then. The year is {YEAR} and there is time."],
        ["Uus nägu. {PLACE} on väike koht, siin märgatakse. # en: A new face. {PLACE} is a small place, people notice.",
         "Mis sa siit otsid? # en: What are you looking for here?"],
    ],
    "newest": [
        ["Sa oled see uus omanik. Ma nägin autot. # en: You're the new owner. I saw the car.",
         "{NPC}. Ära vaata nii, ma kuulen paremini kui sina. # en: {NPC}. Don't look like that, I hear better than you do."],
        ["Tere. Sa vaatad maad nagu keegi, kes tahab midagi leida. # en: Hello. You look at the ground like somebody who wants to find something.",
         "Ma olen siin kogu elu olnud. Küsi. # en: I've been here all my life. Ask."],
    ],
}
GENERIC_MENU = [
    "+ [Mis koht see on? %% What is this place?]",
    "    {PLACE}. Kõik, mis siin on, seisab millegi vanema peal. # en: {PLACE}. Everything here stands on something older.",
    "    -> menu",
    "+ [Ma lähen. %% I'll go.]",
    "    Mine. Ma olen siin. # en: Go. I'm here.",
    "    -> END",
]
EXTERNALS = ["flag(name)", "has_item(id)", "give_item(id, target)", "take_item(id)", "set_flag(name)", "end_chapter()", "chapter()", "trigger(cp_id)", "visiting()"]


def q(s):
    return '"' + str(s).replace('"', '\\"') + '"'


def gd_array(items):
    return "Array[String]([" + ", ".join(q(i) for i in items) + "])"


def load_blocks(blocks_dir=BLOCKS_DIR):
    out = {}
    for f in sorted(os.listdir(blocks_dir)):
        if f.endswith(".json"):
            b = json.load(open(os.path.join(blocks_dir, f), encoding="utf-8"))
            out[b["id"]] = b
    return out


def role_era(role, eras):
    if role == "oldest":
        return eras[0]
    if role == "newest":
        return eras[-1]
    if role == "middle":
        return eras[len(eras) // 2] if len(eras) >= 3 else eras[-1]
    raise ValueError(f"unknown era role {role!r}")


def name_for(year, rng, used):
    for limit, names in NAMES:
        if year < limit:
            pool = [n for n in names if n not in used] or names
            n = rng.choice(pool)
            used.add(n)
            return n
    return "Keegi"


def subst(text, env):
    def rep(m):
        return str(env.get(m.group(1), m.group(0)))
    return re.sub(r"\{([A-Z_]+)\}", rep, text)


def subst_nodes(nodes, env):
    out = []
    for n in nodes:
        n2 = {}
        for k, v in n.items():
            if isinstance(v, str):
                n2[k] = subst(v, env)
            elif isinstance(v, list) and k == "children":
                n2[k] = subst_nodes(v, env)
            else:
                n2[k] = v
        out.append(n2)
    return out


def compose(site, name, years, seed=0, block_ids=None, blocks_dir=BLOCKS_DIR):
    """Returns a dict: eras, npcs, items, cps, nodes, ink, strings, objectives, ending, locations, flags."""
    years = sorted(int(y) for y in years)
    eras = [f"era_{y}" for y in years]
    year_of = dict(zip(eras, years))
    rng = random.Random(seed)
    library = load_blocks(blocks_dir)
    chosen = [library[b] for b in block_ids] if block_ids else list(library.values())
    if len(eras) < 2:
        raise ValueError("a story needs at least two eras")
    # blocks whose origin and trigger fall in the same era make no sense here; drop them
    usable = []
    for b in chosen:
        trig = role_era(b["trigger_era"], eras)
        if b.get("kind") == "delivery" and role_era(b["artifact"]["origin_era"], eras) == trig:
            continue
        usable.append(b)
    rng.shuffle(usable)
    used_names = set()
    npcs = {}
    for e in eras:
        npcs[e] = {"id": f"npc_{e}", "node": f"Local{year_of[e]}", "label": f"NPC_{year_of[e]}", "name": name_for(year_of[e], rng, used_names)}
    base_env = {"PLACE": name, "OLDEST": str(years[0]), "NEWEST": str(years[-1])}
    strings = []
    for e in eras:
        strings.append([npcs[e]["label"], npcs[e]["name"], npcs[e]["name"]])
    items, cps = [], []
    nodes = {e: [] for e in eras}
    menu = {e: [] for e in eras}
    knots = {e: [] for e in eras}
    flags, bonus_flag, coop_flags = [], "", []
    trigger_count = {e: 0 for e in eras}
    locations = {}
    for b in usable:
        trig = role_era(b["trigger_era"], eras)
        cp_id = f"cp_{b['id']}"
        env = dict(base_env, FLAG=b["flag"], CP_ID=cp_id, TARGET_ID=npcs[trig]["id"], TARGET_NPC=npcs[trig]["name"])
        origin = None
        if b.get("kind") == "delivery":
            art = b["artifact"]
            origin = role_era(art["origin_era"], eras)
            env["ITEM"] = art["id"]
            items.append((art["id"] + ".tres", {
                "id": q(art["id"]), "display_name_key": q("ITEM_" + art["id"].upper()), "description_key": q("ITEM_" + art["id"].upper() + "_DESC"),
                "can_cross_eras": "true", "linked_consequence_point_id": q(cp_id), "valid_delivery_target": q(npcs[trig]["id"]),
                "origin_era": q(origin), "delivery_era": q(trig)}))
            nodes[origin].append({"type": "pickup", "name": "Pickup_" + art["id"], "item": art["id"], "examine": "ITEM_" + art["id"].upper() + "_DESC",
                                  "at": {"ref": art["spot"], "offset": art.get("offset", [0, 0])}})
        else:
            sp = b["story_point"]
            nodes[trig].append({"type": "group", "name": sp.get("name", "Story_" + b["id"]) + "Group", "at": sp["spot"], "offset": sp.get("offset", [0, 0]), "children": [
                {"type": "story_point", "name": sp.get("name", "Story_" + b["id"]), "knot": sp["knot"], "speaker": npcs[trig]["label"], "text": sp.get("text", ""),
                 "loc": sp.get("label", ""), "label": sp.get("label", ""), "radius": sp.get("radius", 1.8)}]})
        later = eras[eras.index(trig) + 1:]
        cps.append((cp_id + ".tres", {
            "id": q(cp_id), "flag_name": q(b["flag"]), "trigger_era": q(trig), "affected_eras": gd_array(later),
            "trigger_description_key": q("CP_" + b["id"].upper() + "_TRIGGER"), "effect_description_key": q("CP_" + b["id"].upper() + "_EFFECT")}))
        for e in later:
            nodes[e].extend(subst_nodes(b.get("visible", []), env))
            nodes[e].extend(subst_nodes(b.get("absent", []), env))
        nodes[trig].extend(subst_nodes(b.get("trigger_props", []), env))
        for e in eras:
            roles = ["any"]
            if e == trig:
                roles.append("trigger")
            if origin and e == origin:
                roles.append("origin")
            if e in later:
                roles.append("later")
            if origin and eras.index(e) < eras.index(origin):
                roles.append("before")
            for r in roles:
                for line in b.get("ink", {}).get(r, []):
                    menu[e].append(subst(line, dict(env, YEAR=str(year_of[e]), NPC=npcs[e]["name"])))
        for line in b.get("ink", {}).get("knot", []):
            knots[trig].append(subst(line, dict(env, YEAR=str(year_of[trig]), NPC=npcs[trig]["name"])))
        for k, (et, en) in b.get("strings", {}).items():
            strings.append([k, subst(et, env), subst(en, env)])
            if k.startswith("LOC_"):
                anchor = (b.get("story_point") or {}).get("spot") or (b.get("visible") or [{}])[0].get("at") or "landmark"
                locations[k] = anchor if isinstance(anchor, str) else "landmark"
        if b.get("bonus"):
            bonus_flag = b["flag"]
        elif b.get("coop"):
            coop_flags.append(b["flag"])   # needs a visiting friend; shown in the ledger, not counted for the ending
        else:
            flags.append(b["flag"])
        trigger_count[trig] += 1
    # --- ink per era ------------------------------------------------------------------------------
    ink = {}
    threshold = max(1, (len(flags) + 1) // 2)
    counted_expr = " + ".join(f'flag("{f}")' for f in flags) or "0"
    for e in eras:
        role = "oldest" if e == eras[0] else ("newest" if e == eras[-1] else "middle")
        env = dict(base_env, YEAR=str(year_of[e]), NPC=npcs[e]["name"])
        intro = rng.choice(INTROS[role])
        lines = [f"EXTERNAL {x}" for x in EXTERNALS] + ["-> END", "", "== greeter =="]
        lines.append(f'{{ not flag("met_{e}"):')
        lines.append(f'    ~ set_flag("met_{e}")')
        lines += ["    " + subst(l, env) for l in intro]
        lines += ["- else:", "    Jälle sina. # en: You again.", "}", "-> menu", "", "= menu"]
        lines += menu[e]
        if e == eras[-1]:
            lines += ['+ { chapter() >= 3 and not flag("epilogue") } [Räägime lõpuni. %% Let\'s finish the conversation.]', "    -> sit"]
        lines += [subst(l, env) for l in GENERIC_MENU]
        lines += ["", "= check_chapter", f"{{ chapter() == 2 and ({counted_expr}) >= {threshold}:", "    ~ end_chapter()", "}", "-> menu"]
        if e == eras[-1]:
            lines += ["", "= sit", '~ set_flag("epilogue")', "~ end_chapter()",
                      "Noh. Räägime siis sellest, mis alles on. # en: Well. Let's talk about what's still here.", "-> END"]
        if knots[e]:
            lines += [""] + knots[e]
        ink[e] = "\n".join(lines) + "\n"
    # --- objectives, ending ----------------------------------------------------------------------
    deliver_era = max(eras, key=lambda e: trigger_count[e]) if usable else eras[0]
    objectives = [
        {"when": "register_locked", "key": "OBJ_FIND_REGISTER", "target": "RegisterBook", "lift": 1.2},
        {"chapter": 1, "key": "OBJ_VISIT_ERAS"},
        {"chapter": 2, "key": "OBJ_DELIVER", "target": npcs[deliver_era]["node"], "era": deliver_era, "lift": 2.2},
        {"chapter": 3, "not_flag": "epilogue", "key": "OBJ_SIT", "target": npcs[eras[-1]]["node"], "era": eras[-1], "lift": 2.2},
    ]
    n = len(flags)
    tiers = []
    if n:
        tiers.append(dict({"min_kept": n, "key": "ENDING_ALL"}, **({"bonus": True} if bonus_flag else {})))
        if n >= 2:
            tiers.append({"min_kept": max(1, (n + 1) // 2), "key": "ENDING_SOME"})
    tiers.append({"key": "ENDING_NONE"})
    ending = {"trigger_flag": "epilogue", "counted_flags": flags, "tiers": tiers}
    if bonus_flag:
        ending["bonus_flag"] = bonus_flag
        ending["partial_key"] = "ENDING_BOX_PARTIAL"
    strings += [
        ["OBJ_FIND_REGISTER", "Leia raamat.", "Find the register."],
        ["OBJ_VISIT_ERAS", "Käi läbi kõik aastad.", "Visit every year."],
        ["OBJ_DELIVER", "Vii see, mille leidsid, sinna, kuhu see kuulub.", "Take what you found to where it belongs."],
        ["OBJ_SIT", f"Mine tagasi aastasse {years[-1]} ja räägi lõpuni.", f"Go back to {years[-1]} and finish the conversation."],
        ["ENDING_ALL_TITLE", "Õunaaed", "Orchard"], ["ENDING_ALL", "Kõik, mis sai hoitud, on alles. Kast on kõige vanema puu all, ja selles on kolme põlve paberid.", "Everything that could be kept is here. The box is under the oldest tree, and in it are three generations of papers."],
        ["ENDING_SOME_TITLE", "Vaod", "Furrows"], ["ENDING_SOME", "Jäljed on alles. Mitte kõik, aga need, mis on, näitab {NPC} sulle ükshaaval, kepiga.".replace("{NPC}", npcs[eras[-1]]["name"]), "Traces remain. Not all of them, but the ones that are, {NPC} shows you one by one, with a stick.".replace("{NPC}", npcs[eras[-1]]["name"])],
        ["ENDING_NONE_TITLE", "Mets", "Forest"], ["ENDING_NONE", "Maa võttis suurema osa vaikselt tagasi. Lood räägitakse ikkagi, tamme juurel istudes.", "The land quietly took most of it back. The stories are told anyway, sitting on the oak's roots."],
        ["ENDING_BOX_PARTIAL", "Kastis on kiri ja pressitud õis, aga pabereid ei ole. „Noh. See oli see osa, mis loeb.“", "The box holds the letter and a pressed blossom, but no papers. \"Well. That was the part that mattered.\""],
        ["ENDING_KEPT", "Alles %d / %d", "Kept %d of %d"],
    ]
    return {"eras": eras, "years": years, "npcs": npcs, "items": items, "cps": cps, "nodes": nodes, "ink": ink, "strings": strings,
            "objectives": objectives, "ending": ending, "locations": locations, "blocks": [b["id"] for b in usable], "seed": seed,
            "coop_flags": coop_flags}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--eras", default="1798,1938,2026")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--blocks", help="comma-separated block ids (default: all usable)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    lib = load_blocks()
    if a.list:
        for b in lib.values():
            print(f"{b['id']:10s} {b.get('kind'):9s} trigger {b['trigger_era']:7s} flag {b['flag']:18s} {b.get('title', '')}")
    else:
        c = compose("demo", "Demo", a.eras.split(","), a.seed, a.blocks.split(",") if a.blocks else None)
        print("blocks:", c["blocks"]); print("npcs:", {e: v["name"] for e, v in c["npcs"].items()})
        print("items:", [i[0] for i in c["items"]]); print("cps:", [i[0] for i in c["cps"]])
        for e in c["eras"]:
            print(f"--- {e}: {len(c['nodes'][e])} story nodes, {c['ink'][e].count(chr(10))} ink lines")
        if a.dry_run:
            print(c["ink"][c["eras"][0]])
