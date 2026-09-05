# Headless check of the shared ledger: starts a throwaway SpacetimeDB on 127.0.0.1:3777, publishes the
# prebuilt module as vk-test, seeds it from the Kvissentali pack, joins with two clients, buys a plot as
# one and sees the owner change in the other. Skips (still PASSED) when the spacetime CLI or the built
# wasm is missing, so make test stays green on machines without the toolchain.
#   godot --headless --path . res://tools/godot/town_test.tscn
extends Node

const PORT := 3777
const SERVER := "http://127.0.0.1:3777"
const DB := "vk-test"
const WASM := "server/vakuraamat/target/wasm32-unknown-unknown/release/vakuraamat.wasm"

var _failed := false
var _pid := 0


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[town] FAILED: ", msg)
		_cleanup()
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		print("[town] FAILED: watchdog")
		_cleanup()
		get_tree().quit(2))
	await get_tree().process_frame
	var root := ProjectSettings.globalize_path("res://")
	var cli := _find_cli()
	if cli == "" or not FileAccess.file_exists("res://" + WASM):
		print("[town] PASSED (skipped: no spacetime CLI or module build; run make module)")
		get_tree().quit()
		return
	var env := "PATH=%s:%s" % [cli.get_base_dir(), OS.get_environment("PATH")]
	var data_dir := ProjectSettings.globalize_path("user://cache/town_test")
	DirAccess.make_dir_recursive_absolute(data_dir)
	_pid = OS.create_process("/usr/bin/env", [env, cli, "start", "--listen-addr", "127.0.0.1:%d" % PORT, "--data-dir", data_dir, "--in-memory"])
	_check(_pid > 0, "could not start spacetime")
	var up := false
	for i in 60:
		await get_tree().create_timer(0.5).timeout
		var r: Dictionary = await Locator.http(SERVER + "/v1/ping")
		if r.ok:
			up = true
			break
	_check(up, "server did not answer /v1/ping")
	var out := []
	var code := OS.execute("/usr/bin/env", [env, cli, "publish", "-s", SERVER, "-b", root + WASM, "-y", DB], out, true)
	_check(code == 0, "publish failed: %s" % "\n".join(out))
	out = []
	code = OS.execute("/usr/bin/env", [env, "python3", root + "tools/town_admin.py", "seed", "--site", "kvissentali", "--server", SERVER, "--db", DB, "--debug"], out, true)
	_check(code == 0, "seed failed: %s" % "\n".join(out))

	Sites.select("kvissentali", false)
	var hash := Sites.pack_hash("kvissentali")
	var a := TownLedger.new()
	add_child(a)
	var b := TownLedger.new()
	add_child(b)
	var client_b: VakuraamatModuleClient = load("res://spacetime_bindings/schema/module_vakuraamat_client.gd").new()
	add_child(client_b)
	var joined := {}
	a.state_changed.connect(func(ok, err): joined["a"] = [ok, err])
	b.state_changed.connect(func(ok, err): joined["b"] = [ok, err])
	a.connect_town(SERVER, DB, hash, "Alpha", null, true)
	b.connect_town(SERVER, DB, hash, "Beta", client_b, true)
	for i in 60:
		await get_tree().create_timer(0.25).timeout
		if joined.has("a") and joined.has("b"):
			break
	_check(joined.has("a") and joined.a[0], "A did not join: %s" % str(joined.get("a")))
	_check(joined.has("b") and joined.b[0], "B did not join: %s" % str(joined.get("b")))
	_check(a.me_id() != b.me_id() and a.me_id() > 0, "players must differ: %d %d" % [a.me_id(), b.me_id()])
	_check(a.parcels().size() > 200, "A sees %d parcels" % a.parcels().size())
	_check(a.me().get("cash", 0) == 250000, "starting cash online: %s" % str(a.me().get("cash")))

	var target: Dictionary = a.parcels().filter(func(p): return p.sellable and p.for_sale and int(p.price) <= 200000 and a.tenants_of(p.tunnus).size() > 0)[0]
	var err: String = await a.buy(target.tunnus)
	_check(err == "", "buy over the wire: %s" % err)
	_check(await a.buy(target.tunnus) == "LEDGER_ALREADY_OWNER", "server error keys must reach the client")
	var seen := false
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if int(b.parcel(target.tunnus).get("owner_id", 0)) == a.me_id():
			seen = true
			break
	_check(seen, "B never saw A's purchase")
	_check(int(a.me().get("cash", 0)) == 250000 - int(target.price), "A's cash after buying: %s" % str(a.me().get("cash")))
	err = await b.place_bid(target.tunnus, 1000)
	_check(err == "", "B's bid: %s" % err)
	var bid_seen := false
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if a.bids_for(target.tunnus).size() == 1:
			bid_seen = true
			break
	_check(bid_seen, "A never saw B's bid")
	err = await a.accept_bid(int(a.bids_for(target.tunnus)[0].id))
	_check(err == "", "accept: %s" % err)
	var moved := false
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if int(b.parcel(target.tunnus).get("owner_id", 0)) == b.me_id():
			moved = true
			break
	_check(moved, "ownership did not move to B after accept")
	_check(await a.grant_cash(5000) == "", "grant_cash on a debug town")
	a.move_to(10.0, 20.0, 0.5)
	var present := false
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if b.presences().size() == 1 and absf(float(b.presences()[0].x) - 10.0) < 0.01:
			present = true
			break
	_check(present, "B never saw A's presence")
	a.disconnect_town()
	b.disconnect_town()
	_cleanup()
	if not _failed:
		print("[town] PASSED")
		get_tree().quit()


func _find_cli() -> String:
	for p in [OS.get_environment("HOME") + "/.local/bin/spacetime", "/opt/homebrew/bin/spacetime", "/usr/local/bin/spacetime"]:
		if FileAccess.file_exists(p):
			return p
	return ""


func _cleanup() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = 0
