# Autoload "Ledger": the one place the game reads and changes the town's economic state.
# Backends: LocalLedger (offline) and, when a town is reachable, TownLedger (the only file that touches the SDK).
# UI and world code only ever talk to this facade; actions return "" or a LEDGER_* translation key.
extends Node

signal parcel_changed(tunnus: String)      # "" = many parcels
signal player_changed
signal month_changed(month: int)
signal event_added(e: Dictionary)
signal bids_changed(tunnus: String)
signal status_changed(online: bool, text: String)

const SETTINGS := "user://settings.cfg"

var online := false
var town_name := ""
var _local: LocalLedger
var _seconds := 0.0
var _running := false


func _process(delta: float) -> void:
	if not _running or _local == null or online:
		return
	_seconds += delta
	var per := float(_local.config.get("seconds_per_month", 600))
	if _seconds >= per:
		_seconds -= per
		_local.advance_month()
		_after_month()


## Called by the world once the layer stands. Tries the town later (TownLedger); for now the local book.
func start(pack: String) -> void:
	if _local == null or _local.pack != pack:
		reset_local(pack)
	_running = true
	status_changed.emit(false, tr("NOTICE_TOWN_OFFLINE"))


func stop() -> void:
	_running = false


## A fresh offline book for a new game.
func reset_local(pack: String) -> void:
	_local = LocalLedger.new()
	_local.start(pack, player_name())
	_seconds = 0.0
	online = false
	town_name = ""
	parcel_changed.emit("")
	player_changed.emit()
	month_changed.emit(_local.month)


func local() -> LocalLedger:
	return _local


func player_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return str(cfg.get_value("player", "name", ""))
	return ""


# ---------------------------------------------------------------- queries

func parcels() -> Array:
	return _local.parcels.values() if _local else []


func parcel(tunnus: String) -> Dictionary:
	return _local.parcel(tunnus) if _local else {}


func tenants_of(tunnus: String) -> Array:
	return _local.tenants_of(tunnus) if _local else []


func improvements_of(tunnus: String) -> Array:
	return _local.improvements_of(tunnus) if _local else []


func structures() -> Array:
	return _local.structures.values() if _local else []


func owner_of(tunnus: String) -> int:
	return int(parcel(tunnus).get("owner_id", 0))


func is_mine(tunnus: String) -> bool:
	return _local != null and owner_of(tunnus) == _local.me_id and _local.me_id != 0


func me() -> Dictionary:
	return _local.me() if _local else {}


func cash() -> int:
	return int(me().get("cash", 0))


func month() -> int:
	return _local.month if _local else 0


func price_index() -> int:
	return _local.price_index if _local else 1000


func yield_of(tunnus: String) -> int:
	return _local.yield_of(tunnus) if _local else 0


func events(limit: int = 50, mine_only: bool = false) -> Array:
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
	return _local.bids_for(tunnus) if _local else []


func my_bids() -> Array:
	return _local.my_bids() if _local else []


func obligations(unpaid_only: bool = true) -> Array:
	return _local.my_obligations(unpaid_only) if _local else []


func monthly_income() -> int:
	var total := 0
	if _local:
		for p in _local.parcels.values():
			if int(p.owner_id) == _local.me_id:
				total += _local.yield_of(p.tunnus)
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


# ---------------------------------------------------------------- actions

func buy(tunnus: String) -> String:
	return _act(_local.buy(_local.me_id, tunnus) if _local else "LEDGER_NO_PARCEL", tunnus)


func list_for_sale(tunnus: String, price: int) -> String:
	return _act(_local.list_for_sale(_local.me_id, tunnus, price) if _local else "LEDGER_NOT_OWNER", tunnus)


func place_bid(tunnus: String, amount: int) -> String:
	var err := _act(_local.place_bid(_local.me_id, tunnus, amount) if _local else "LEDGER_NO_PARCEL", tunnus)
	if err == "":
		bids_changed.emit(tunnus)
	return err


func withdraw_bid(bid_id: int) -> String:
	var err := _act(_local.withdraw_bid(_local.me_id, bid_id) if _local else "LEDGER_NO_BID", "")
	if err == "":
		bids_changed.emit("")
	return err


func accept_bid(bid_id: int) -> String:
	var err := _act(_local.accept_bid(_local.me_id, bid_id) if _local else "LEDGER_NO_BID", "")
	if err == "":
		bids_changed.emit("")
	return err


func pay(obligation_id: int) -> String:
	return _act(_local.pay_obligation(_local.me_id, obligation_id) if _local else "LEDGER_NO_OBLIGATION", "")


func build(tunnus: String, structure_id: String) -> String:
	return _act(_local.build(_local.me_id, tunnus, structure_id) if _local else "LEDGER_NOT_OWNER", tunnus)


func press_tenant(tunnus: String) -> String:
	return _act(_local.press_tenant(_local.me_id, tunnus) if _local else "LEDGER_NOT_OWNER", tunnus)


func buy_arrears(tunnus: String) -> String:
	return _act(_local.buy_arrears(_local.me_id, tunnus) if _local else "LEDGER_NO_PARCEL", tunnus)


func donate(amount: int) -> String:
	return _act(_local.donate(_local.me_id, amount) if _local else "LEDGER_NO_MONEY", "")


func debug_grant(amount: int) -> void:
	if _local:
		_local.grant(_local.me_id, amount)
		player_changed.emit()


func debug_advance_month() -> void:
	if _local:
		_local.advance_month()
		_after_month()


# ---------------------------------------------------------------- persistence

func to_dict() -> Dictionary:
	return {"backend": "local", "local": _local.to_dict()} if _local else {}


func from_dict(d: Dictionary) -> void:
	var l: Dictionary = d.get("local", {})
	var pack := str(l.get("pack", Sites.active))
	reset_local(pack if pack != "" else Sites.active)
	if not l.is_empty():
		_local.from_dict(l)
	parcel_changed.emit("")
	player_changed.emit()
	month_changed.emit(_local.month)


# ---------------------------------------------------------------- internals

func _act(err: String, tunnus: String) -> String:
	if err == "":
		SaveManager.mark_dirty()
		parcel_changed.emit(tunnus)
		player_changed.emit()
		var last: Array = events(1)
		if last.size() > 0:
			event_added.emit(last[0])
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
