# Autoload "Ledger": the one place the game reads and changes the town's economic state.
# Backends: LocalLedger (offline) and, when a town is reachable, TownLedger (the only file that touches the SDK).
# UI and world code only ever talk to this facade; actions are coroutines returning "" or a LEDGER_* key.
extends Node

signal parcel_changed(tunnus: String)      # "" = many parcels
signal player_changed
signal month_changed(month: int)
signal event_added(e: Dictionary)
signal bids_changed(tunnus: String)
signal presence_changed
signal status_changed(online: bool, text: String)

const SETTINGS := "user://settings.cfg"
const DEFAULT_TOWN_URL := "http://127.0.0.1:3300"
const MOVE_INTERVAL := 1.0

var online := false
var town_name := ""
var town_url := ""
var _local: LocalLedger
var _town: TownLedger
var _seconds := 0.0
var _running := false
var _last_month := 0
var _move_t := 0.0
var _last_event_id := 0


func _process(delta: float) -> void:
	if not _running or _local == null or online:
		return
	_seconds += delta
	var per := float(_local.config.get("seconds_per_month", 600))
	if _seconds >= per:
		_seconds -= per
		_local.advance_month()
		_after_month()


## Called by the world once the layer stands: try the town named by the pack, else the local book.
func start(pack: String) -> void:
	if _local == null or _local.pack != pack:
		reset_local(pack)
	_running = true
	town_url = setting("town", "url", DEFAULT_TOWN_URL)
	town_name = db_name_for(pack)
	if bool(setting("town", "offline", false)) or DisplayServer.get_name() == "headless" and not bool(setting("town", "headless_ok", false)):
		status_changed.emit(false, tr("UI_OFFLINE"))
		return
	var probe: Dictionary = await Locator.http(town_url.trim_suffix("/") + "/v1/database/" + town_name + "/identity")
	if not probe.ok:
		EventBus.notice.emit(tr("NOTICE_TOWN_OFFLINE"))
		status_changed.emit(false, tr("UI_OFFLINE"))
		return
	if _town == null:
		_town = TownLedger.new()
		_town.name = "Town"
		add_child(_town)
		_town.state_changed.connect(_on_town_state)
		_town.rows_changed.connect(_on_rows)
	_town.connect_town(town_url, town_name, Sites.pack_hash(pack), player_name())


func stop() -> void:
	_running = false
	if _town:
		_town.disconnect_town()
	online = false


## A fresh offline book for a new game.
func reset_local(pack: String) -> void:
	_local = LocalLedger.new()
	_local.start(pack, player_name())
	_seconds = 0.0
	if not online:
		parcel_changed.emit("")
		player_changed.emit()
		month_changed.emit(_local.month)


func local() -> LocalLedger:
	return _local


func player_name() -> String:
	return str(setting("player", "name", ""))


static func setting(section: String, key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return cfg.get_value(section, key, default)
	return default


## Town database name: the tile centre plus a hash of the pack's parcel and tenant files (tools/town_admin.py name).
static func db_name_for(pack: String) -> String:
	var m := Sites.manifest_for(pack)
	var c: Array = m.get("terrain", {}).get("center", [0, 0])
	return "vk-t%d-%d-%s" % [int(c[0]), int(c[1]), Sites.pack_hash(pack)]


# ---------------------------------------------------------------- queries

func parcels() -> Array:
	if online:
		return _town.parcels()
	return _local.parcels.values() if _local else []


func parcel(tunnus: String) -> Dictionary:
	if online:
		return _town.parcel(tunnus)
	return _local.parcel(tunnus) if _local else {}


func tenants_of(tunnus: String) -> Array:
	if online:
		return _town.tenants_of(tunnus)
	return _local.tenants_of(tunnus) if _local else []


func improvements_of(tunnus: String) -> Array:
	if online:
		return _town.improvements_of(tunnus)
	return _local.improvements_of(tunnus) if _local else []


func structures() -> Array:
	if online:
		var out := []
		for s in _town.structures():
			var d: Dictionary = _local.structures.get(s.id, {}) if _local else {}
			s["purposes"] = Array(str(s.get("purposes", "")).split(",", false))
			s["display_name_key"] = d.get("display_name_key", "")
			s["description_key"] = d.get("description_key", "")
			out.append(s)
		return out
	return _local.structures.values() if _local else []


func me_id() -> int:
	return _town.me_id() if online else (_local.me_id if _local else 0)


func owner_of(tunnus: String) -> int:
	return int(parcel(tunnus).get("owner_id", 0))


func is_mine(tunnus: String) -> bool:
	var id := me_id()
	return id != 0 and owner_of(tunnus) == id


func me() -> Dictionary:
	if online:
		return _town.me()
	return _local.me() if _local else {}


func players() -> Array:
	return _town.players() if online else ([_local.me()] if _local else [])


func presences() -> Array:
	return _town.presences() if online else []


func cash() -> int:
	return int(me().get("cash", 0))


func month() -> int:
	if online:
		return int(_town.town().get("month", 0))
	return _local.month if _local else 0


func price_index() -> int:
	if online:
		return int(_town.town().get("price_index_permille", 1000))
	return _local.price_index if _local else 1000


func yield_of(tunnus: String) -> int:
	var p := parcel(tunnus)
	if p.is_empty():
		return 0
	var bonus := 0
	for i in improvements_of(tunnus):
		for s in structures():
			if s.id == i.structure_id:
				bonus += int(s.rent_bonus)
	return int(p.rent_month) + bonus


func events(limit: int = 50, mine_only: bool = false) -> Array:
	if online:
		return _town.events(limit, mine_only)
	if _local == null:
		return []
	var out := []
	for i in range(_local.events.size() - 1, -1, -1):
		var e: Dictionary = _local.events[i]
		if mine_only and int(e.actor_id) != _local.me_id:
			continue
		out.append(e)
		if out.size() >= limit:
			break
	return out


func bids_for(tunnus: String) -> Array:
	if online:
		return _town.bids_for(tunnus)
	return _local.bids_for(tunnus) if _local else []


func my_bids() -> Array:
	if online:
		return _town.my_bids()
	return _local.my_bids() if _local else []


func obligations(unpaid_only: bool = true) -> Array:
	if online:
		return _town.my_obligations(unpaid_only)
	return _local.my_obligations(unpaid_only) if _local else []


func monthly_income() -> int:
	var total := 0
	for p in parcels():
		if is_mine(p.tunnus):
			total += yield_of(p.tunnus)
	return total


## "september 2026": the pack's terrain date plus the elapsed months.
func date_string() -> String:
	var t: Dictionary = Sites.get_value("terrain", {})
	var date: Array = t.get("date", [2026, 1, 1]) if typeof(t) == TYPE_DICTIONARY else [2026, 1, 1]
	var idx := int(date[1]) - 1 + month()
	var year := int(date[0]) + int(idx / 12)
	return "%s %d" % [tr("MONTH_%d" % (idx % 12 + 1)), year]


func format_money(amount: int) -> String:
	return "%d %s" % [amount, tr("CUR_EUR")]


# ---------------------------------------------------------------- actions (await them)

func buy(tunnus: String) -> String:
	return _act(await _town.buy(tunnus) if online else (_local.buy(_local.me_id, tunnus) if _local else "LEDGER_NO_PARCEL"), tunnus)


func list_for_sale(tunnus: String, price: int) -> String:
	return _act(await _town.list_for_sale(tunnus, price) if online else (_local.list_for_sale(_local.me_id, tunnus, price) if _local else "LEDGER_NOT_OWNER"), tunnus)


func place_bid(tunnus: String, amount: int) -> String:
	var err := _act(await _town.place_bid(tunnus, amount) if online else (_local.place_bid(_local.me_id, tunnus, amount) if _local else "LEDGER_NO_PARCEL"), tunnus)
	if err == "":
		bids_changed.emit(tunnus)
	return err


func withdraw_bid(bid_id: int) -> String:
	var err := _act(await _town.withdraw_bid(bid_id) if online else (_local.withdraw_bid(_local.me_id, bid_id) if _local else "LEDGER_NO_BID"), "")
	if err == "":
		bids_changed.emit("")
	return err


func accept_bid(bid_id: int) -> String:
	var err := _act(await _town.accept_bid(bid_id) if online else (_local.accept_bid(_local.me_id, bid_id) if _local else "LEDGER_NO_BID"), "")
	if err == "":
		bids_changed.emit("")
	return err


func pay(obligation_id: int) -> String:
	return _act(await _town.pay_obligation(obligation_id) if online else (_local.pay_obligation(_local.me_id, obligation_id) if _local else "LEDGER_NO_OBLIGATION"), "")


func build(tunnus: String, structure_id: String) -> String:
	return _act(await _town.build(tunnus, structure_id) if online else (_local.build(_local.me_id, tunnus, structure_id) if _local else "LEDGER_NOT_OWNER"), tunnus)


func press_tenant(tunnus: String) -> String:
	return _act(await _town.press_tenant(tunnus) if online else (_local.press_tenant(_local.me_id, tunnus) if _local else "LEDGER_NOT_OWNER"), tunnus)


func buy_arrears(tunnus: String) -> String:
	return _act(await _town.buy_arrears(tunnus) if online else (_local.buy_arrears(_local.me_id, tunnus) if _local else "LEDGER_NO_PARCEL"), tunnus)


func donate(amount: int) -> String:
	return _act(await _town.donate(amount) if online else (_local.donate(_local.me_id, amount) if _local else "LEDGER_NO_MONEY"), "")


## Presence, at most once a second, town only.
func move(pos: Vector3, yaw: float) -> void:
	if not online:
		return
	_move_t += get_process_delta_time()
	if _move_t >= MOVE_INTERVAL:
		_move_t = 0.0
		_town.move_to(pos.x, pos.z, yaw)


func debug_grant(amount: int) -> void:
	if online:
		var err: String = await _town.grant_cash(amount)
		if err != "":
			EventBus.notice.emit(tr(err))
	elif _local:
		_local.grant(_local.me_id, amount)
		player_changed.emit()


func debug_advance_month() -> void:
	if online:
		EventBus.notice.emit(tr("LEDGER_OFFLINE_ONLY"))
	elif _local:
		_local.advance_month()
		_after_month()


# ---------------------------------------------------------------- persistence (offline book only)

func to_dict() -> Dictionary:
	if online:
		return {"backend": "town", "town": town_name, "url": town_url}
	return {"backend": "local", "local": _local.to_dict()} if _local else {}


func from_dict(d: Dictionary) -> void:
	var l: Dictionary = d.get("local", {})
	var pack := str(l.get("pack", Sites.active))
	reset_local(pack if pack != "" else Sites.active)
	if not l.is_empty():
		_local.from_dict(l)
	if not online:
		parcel_changed.emit("")
		player_changed.emit()
		month_changed.emit(_local.month)


# ---------------------------------------------------------------- internals

func _on_town_state(ok: bool, err: String) -> void:
	var was := online
	online = ok
	if ok:
		_last_month = month()
		_last_event_id = int(events(1)[0].id) if events(1).size() > 0 else 0
		status_changed.emit(true, tr("UI_ONLINE") % town_name)
		if not was:
			EventBus.notice.emit(tr("NOTICE_TOWN_ONLINE") % Sites.display_name(Sites.active))
		parcel_changed.emit("")
		player_changed.emit()
		month_changed.emit(month())
		presence_changed.emit()
	else:
		status_changed.emit(false, tr(err) if err.begins_with("LEDGER_") else err)
		if was or err.begins_with("LEDGER_"):
			EventBus.notice.emit(tr(err) if err.begins_with("LEDGER_") else tr("NOTICE_TOWN_OFFLINE"))
		parcel_changed.emit("")
		player_changed.emit()


func _on_rows(table: String, key: String) -> void:
	if not online:
		return
	match table:
		"parcel", "improvement", "tenant":
			parcel_changed.emit(key)
		"player":
			player_changed.emit()
		"bid":
			bids_changed.emit(key)
		"obligation":
			player_changed.emit()
		"presence":
			presence_changed.emit()
		"town":
			var m := month()
			if m != _last_month:
				_last_month = m
				month_changed.emit(m)
				EventBus.notice.emit(tr("NOTICE_MONTH") % date_string())
		"event":
			var latest := events(1)
			if latest.size() > 0 and int(latest[0].id) != _last_event_id:
				_last_event_id = int(latest[0].id)
				event_added.emit(latest[0])
		_:
			parcel_changed.emit("")


func _act(err: String, tunnus: String) -> String:
	if err == "":
		if not online:
			SaveManager.mark_dirty()
			var last: Array = events(1)
			if last.size() > 0:
				event_added.emit(last[0])
		parcel_changed.emit(tunnus)
		player_changed.emit()
	return err


func _after_month() -> void:
	SaveManager.mark_dirty()
	month_changed.emit(_local.month)
	parcel_changed.emit("")
	player_changed.emit()
	for e in events(8):
		if int(e.month) == _local.month:
			event_added.emit(e)
	EventBus.notice.emit(tr("NOTICE_MONTH") % date_string())
