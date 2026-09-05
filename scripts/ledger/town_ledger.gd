# The online backend of the Ledger: one town = one SpacetimeDB database. This is the only script that
# touches the SDK (generated bindings under spacetime_bindings/, the SpacetimeDB autoload). It connects,
# keeps the identity token in settings.cfg, subscribes to every public table, joins the town and turns
# row updates into Ledger signals. Rows are handed out as Dictionaries with the server's field names.
class_name TownLedger
extends Node

signal state_changed(ok: bool, err: String)   # joined, or why not (a LEDGER_* key or a transport message)
signal rows_changed(table: String, key: String)

const SETTINGS := "user://settings.cfg"

var url := ""
var db_name := ""
var pack_hash := ""
var my_name := ""
var joined := false
var _client: VakuraamatModuleClient
var _me_id := 0
var _sub: SpacetimeDBSubscription
var _keep_token := true


## `client` defaults to the SpacetimeDB autoload's module client; tests pass a second instance.
## `fresh_identity` ignores the saved token (a new anonymous player).
func connect_town(p_url: String, p_db: String, p_hash: String, p_name: String, client: VakuraamatModuleClient = null, fresh_identity: bool = false) -> void:
	url = p_url
	db_name = p_db
	pack_hash = p_hash
	my_name = p_name
	_client = client if client else SpacetimeDB.Vakuraamat
	_keep_token = client == null
	var options := SpacetimeDBConnectionOptions.new()
	options.compression = SpacetimeDBConnection.CompressionPreference.NONE
	options.one_time_token = fresh_identity
	options.save_token = false
	options.token = "" if fresh_identity else _saved_token()
	options.threading = DisplayServer.get_name() != "headless"
	options.auto_reconnect = true
	options.max_reconnect_attempts = 0
	if not _client.connected.is_connected(_on_connected):
		_client.connected.connect(_on_connected)
		_client.connection_error.connect(_on_error)
		_client.disconnected.connect(_on_disconnected)
		_client.reconnected.connect(_on_reconnected)
	_client.connect_db(url, db_name, options)


func disconnect_town() -> void:
	joined = false
	if _client and _client.is_connected_db():
		_client.disconnect_db()


func _on_connected(identity: PackedByteArray, token: String) -> void:
	if _keep_token:
		_save_token(token)
	_sub = _client.subscribe_all_tables()
	if _sub.error != OK:
		state_changed.emit(false, "subscribe failed")
		return
	var err: Error = await _sub.wait_for_applied(10.0)
	if err != OK:
		state_changed.emit(false, "subscription not applied")
		return
	_wire_rows()
	var call: SpacetimeDBReducerCall = await _client.reducers.join_town(pack_hash, my_name).wait_for_response()
	if not call.is_ok():
		state_changed.emit(false, _err(call))
		return
	var me_row := _find_me(identity)
	_me_id = int(me_row.get("id", 0))
	joined = _me_id != 0
	state_changed.emit(joined, "" if joined else "LEDGER_NOT_JOINED")


func _on_reconnected() -> void:
	var call: SpacetimeDBReducerCall = await _client.reducers.join_town(pack_hash, my_name).wait_for_response()
	joined = call.is_ok()
	rows_changed.emit("", "")
	state_changed.emit(joined, "" if joined else _err(call))


func _on_error(code: int, reason: String) -> void:
	joined = false
	state_changed.emit(false, "%d %s" % [code, reason])


func _on_disconnected() -> void:
	joined = false
	state_changed.emit(false, "disconnected")


func _wire_rows() -> void:
	var db: VakuraamatModuleDb = _client.db
	db.parcel.on_insert(func(r): rows_changed.emit("parcel", r.tunnus))
	db.parcel.on_update(func(_o, r): rows_changed.emit("parcel", r.tunnus))
	db.player.on_insert(func(_r): rows_changed.emit("player", ""))
	db.player.on_update(func(_o, _r): rows_changed.emit("player", ""))
	db.town.on_update(func(_o, _r): rows_changed.emit("town", ""))
	db.event.on_insert(func(r): rows_changed.emit("event", str(r.id)))
	db.bid.on_insert(func(r): rows_changed.emit("bid", r.tunnus))
	db.bid.on_update(func(_o, r): rows_changed.emit("bid", r.tunnus))
	db.obligation.on_insert(func(_r): rows_changed.emit("obligation", ""))
	db.obligation.on_update(func(_o, _r): rows_changed.emit("obligation", ""))
	db.improvement.on_insert(func(r): rows_changed.emit("improvement", r.tunnus))
	db.tenant.on_update(func(_o, r): rows_changed.emit("tenant", r.tunnus))
	db.presence.on_insert(func(_r): rows_changed.emit("presence", ""))
	db.presence.on_update(func(_o, _r): rows_changed.emit("presence", ""))
	db.presence.on_delete(func(_r): rows_changed.emit("presence", ""))


# ---------------------------------------------------------------- queries (Dictionaries)

func ready_db() -> bool:
	return _client != null and _client.db != null and joined


func me_id() -> int:
	return _me_id


func parcels() -> Array:
	return _rows(_client.db.parcel.iter()) if ready_db() else []


func parcel(tunnus: String) -> Dictionary:
	if not ready_db():
		return {}
	var r = _client.db.parcel.tunnus.find(tunnus)
	return _row(r) if r else {}


func tenants_of(tunnus: String) -> Array:
	return _rows(_client.db.tenant.tunnus.filter(tunnus)) if ready_db() else []


func improvements_of(tunnus: String) -> Array:
	return _rows(_client.db.improvement.tunnus.filter(tunnus)) if ready_db() else []


func structures() -> Array:
	return _rows(_client.db.structure.iter()) if ready_db() else []


func me() -> Dictionary:
	if not ready_db():
		return {}
	var r = _client.db.player.id.find(_me_id)
	return _row(r) if r else {}


func players() -> Array:
	return _rows(_client.db.player.iter()) if ready_db() else []


func town() -> Dictionary:
	if not ready_db():
		return {}
	var r = _client.db.town.id.find(0)
	return _row(r) if r else {}


func events(limit: int, mine_only: bool) -> Array:
	if not ready_db():
		return []
	var all := _rows(_client.db.event.iter())
	all.sort_custom(func(a, b): return int(a.id) > int(b.id))
	var out := []
	for e in all:
		if mine_only and int(e.actor_id) != _me_id:
			continue
		out.append(e)
		if out.size() >= limit:
			break
	return out


func bids_for(tunnus: String) -> Array:
	return _rows(_client.db.bid.tunnus.filter(tunnus)).filter(func(b): return int(b.status) == 0) if ready_db() else []


func my_bids() -> Array:
	return _rows(_client.db.bid.iter()).filter(func(b): return int(b.bidder_id) == _me_id and int(b.status) == 0) if ready_db() else []


func my_obligations(unpaid_only: bool) -> Array:
	return _rows(_client.db.obligation.player_id.filter(_me_id)).filter(func(o): return not unpaid_only or not o.paid) if ready_db() else []


func presences() -> Array:
	return _rows(_client.db.presence.iter()).filter(func(p): return int(p.player_id) != _me_id) if ready_db() else []


# ---------------------------------------------------------------- actions (await; "" = ok)

func buy(tunnus: String) -> String:
	return await _call(_client.reducers.buy_parcel(tunnus))


func list_for_sale(tunnus: String, price: int) -> String:
	return await _call(_client.reducers.list_for_sale(tunnus, price))


func place_bid(tunnus: String, amount: int) -> String:
	return await _call(_client.reducers.place_bid(tunnus, amount))


func withdraw_bid(bid_id: int) -> String:
	return await _call(_client.reducers.withdraw_bid(bid_id))


func accept_bid(bid_id: int) -> String:
	return await _call(_client.reducers.accept_bid(bid_id))


func pay_obligation(obligation_id: int) -> String:
	return await _call(_client.reducers.pay_obligation(obligation_id))


func build(tunnus: String, structure_id: String) -> String:
	return await _call(_client.reducers.build(tunnus, structure_id))


func press_tenant(tunnus: String) -> String:
	return await _call(_client.reducers.press_tenant(tunnus))


func buy_arrears(tunnus: String) -> String:
	return await _call(_client.reducers.buy_arrears(tunnus))


func donate(amount: int) -> String:
	return await _call(_client.reducers.donate(amount))


func grant_cash(amount: int) -> String:
	return await _call(_client.reducers.grant_cash(amount))


func move_to(x: float, z: float, yaw: float) -> void:
	if ready_db():
		_client.reducers.move_to(x, z, yaw)


# ---------------------------------------------------------------- internals

func _call(c: SpacetimeDBReducerCall) -> String:
	if not ready_db():
		return "LEDGER_NOT_JOINED"
	var done: SpacetimeDBReducerCall = await c.wait_for_response()
	return "" if done.is_ok() else _err(done)


static func _err(c: SpacetimeDBReducerCall) -> String:
	var msg := str(c.error_message)
	var i := msg.find("LEDGER_")
	if i >= 0:
		var j := i
		while j < msg.length() and (msg[j] == "_" or msg[j].to_upper() == msg[j] and msg[j] != " " and msg[j] != '"'):
			j += 1
		return msg.substr(i, j - i)
	return msg if msg != "" else "LEDGER_FAILED"


func _find_me(identity: PackedByteArray) -> Dictionary:
	for r in _client.db.player.iter():
		if r.identity == identity:
			return _row(r)
	return {}


static func _rows(list: Array) -> Array:
	var out := []
	for r in list:
		out.append(_row(r))
	return out


static func _row(r: Resource) -> Dictionary:
	var d := {}
	if r == null:
		return d
	for k in r.BSATN_TYPES:
		d[str(k)] = r.get(k)
	return d


func _saved_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return str(cfg.get_value("town", "token", ""))
	return ""


func _save_token(token: String) -> void:
	if token == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("town", "token", token)
	cfg.save(SETTINGS)
