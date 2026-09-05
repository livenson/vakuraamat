# The offline town ledger: the same rules as server/vakuraamat, run locally from the pack's
# parcels.json, tenants.json, the structures registry and assets/data/economy.json. Money is whole
# euros; the period is a month. Rows use the server's field names so the Ledger facade and the UI
# do not care which backend is live. Never references the town client SDK (ledger_test greps for it).
class_name LocalLedger
extends RefCounted

const ECONOMY := "res://assets/data/economy.json"
const EVENT_KEEP := 300
const BID_LIFE_MONTHS := 3

var pack := ""
var config: Dictionary = {}
var parcels: Dictionary = {}       # tunnus -> row
var tenants: Dictionary = {}       # tunnus -> Array of rows
var players: Dictionary = {}       # id -> row
var structures: Dictionary = {}    # id -> {id, cost, rent_bonus, requires, purposes, display_name_key, description_key}
var bids: Array = []
var obligations: Array = []
var improvements: Array = []
var events: Array = []
var me_id := 1
var month := 0
var price_index := 1000            # permille, 1000 = par
var rng := RandomNumberGenerator.new()
var _next_id := 1


func start(p_pack: String, player_name: String, seed_value: int = 0) -> void:
	pack = p_pack
	rng.seed = seed_value if seed_value != 0 else hash(p_pack)
	config = _load_json(ECONOMY)
	parcels.clear(); tenants.clear(); players.clear(); structures.clear()
	bids.clear(); obligations.clear(); improvements.clear(); events.clear()
	month = 0
	price_index = 1000
	_next_id = 1
	for u in Parcels.units(pack):
		var purpose: String = u.purpose[0] if u.get("purpose", []).size() > 0 else "SIHTOTSTARBETA_MAA"
		var lv := int(u.get("land_value", 0) if u.get("land_value") != null else 0)
		if lv <= 0:
			lv = _fallback_value(purpose, int(u.get("area", 0)))
		var sellable: bool = lv > 0 and not (u.get("ownership", "") in config.get("unsellable_ownership", [])) \
			and not (purpose in config.get("unsellable_purpose", []))
		parcels[u.tunnus] = {"tunnus": u.tunnus, "address": str(u.get("address", "")), "purpose": purpose, "area": int(u.get("area", 0)),
			"land_value": lv, "price": list_price(lv), "rent_month": rent_month(lv, purpose), "owner_id": 0,
			"owner_name": str(u.get("ownership", "")), "for_sale": sellable, "sellable": sellable, "x": float(u.get("x", 0)), "z": float(u.get("z", 0))}
	var tpath := Sites.path_in(pack, "tenants.json")
	if FileAccess.file_exists(tpath):
		for t in _load_json(tpath).get("tenants", []):
			if t.get("match") == "exact" and t.get("tunnus") != null and parcels.has(t.tunnus):
				tenants.get_or_add(t.tunnus, []).append({"id": _id(), "tunnus": t.tunnus, "name": str(t.name), "registry_code": str(t.registry_code),
					"legal_form": str(t.get("legal_form", "")), "status": str(t.get("status", "")), "since": str(t.get("since", "")), "arrears": 0})
	var defs := {}
	Sites.load_dir(Sites.data_dir("structures"), defs)
	for sid in defs:
		var s: StructureDefinition = defs[sid]
		structures[sid] = {"id": sid, "cost": s.cost_money, "rent_bonus": s.rent_bonus, "requires": s.requires, "purposes": s.purposes.duplicate(),
			"display_name_key": s.display_name_key, "description_key": s.description_key}
	me_id = add_player(player_name)
	_event("tick", "Town opened with %d parcels" % parcels.size(), "", 0, 0)


func add_player(pname: String) -> int:
	var id := _id()
	players[id] = {"id": id, "name": pname if pname != "" else "Player", "cash": int(config.get("starting_cash", 250000)), "favours": 0, "heat": 0,
		"reputation": 0, "online": true, "joined_month": month}
	return id


# ---------------------------------------------------------------- rules (mirror server/vakuraamat/rules)

func yield_permille(purpose: String) -> int:
	var y: Dictionary = config.get("yield_by_purpose", {})
	return int(round(float(y.get(purpose, y.get("default", 0.01))) * 1000))


func rent_month(land_value: int, purpose: String) -> int:
	var yp := yield_permille(purpose)
	if land_value <= 0 or yp <= 0:
		return 0
	return maxi(1, int(land_value * yp / 1000 / 12))


func tax_month(land_value: int) -> int:
	return int(land_value * int(round(float(config.get("tax_rate_year", 0.005)) * 1000)) / 1000 / 12)


func list_price(land_value: int) -> int:
	return maxi(1, int(land_value * price_index / 1000))


func _fallback_value(purpose: String, area: int) -> int:
	var r: Dictionary = config.get("land_rate_per_m2", {})
	return int(area * float(r.get(purpose, r.get("default", 2.0))))


# ---------------------------------------------------------------- queries

func me() -> Dictionary:
	return players.get(me_id, {})


func parcel(tunnus: String) -> Dictionary:
	return parcels.get(tunnus, {})


func tenants_of(tunnus: String) -> Array:
	return tenants.get(tunnus, [])


func improvements_of(tunnus: String) -> Array:
	return improvements.filter(func(i): return i.tunnus == tunnus)


func yield_of(tunnus: String) -> int:
	var p := parcel(tunnus)
	if p.is_empty():
		return 0
	var bonus := 0
	for i in improvements_of(tunnus):
		bonus += int(structures.get(i.structure_id, {}).get("rent_bonus", 0))
	return int(p.rent_month) + bonus


func bids_for(tunnus: String) -> Array:
	return bids.filter(func(b): return b.tunnus == tunnus and b.status == 0)


func my_bids() -> Array:
	return bids.filter(func(b): return b.bidder_id == me_id and b.status == 0)


func my_obligations(unpaid_only: bool = true) -> Array:
	return obligations.filter(func(o): return o.player_id == me_id and (not unpaid_only or not o.paid))


# ---------------------------------------------------------------- actions ("" = ok, else an error key)

func buy(actor: int, tunnus: String) -> String:
	var p := parcel(tunnus)
	var me_row: Dictionary = players.get(actor, {})
	if p.is_empty() or me_row.is_empty():
		return "LEDGER_NO_PARCEL"
	if int(p.owner_id) == actor:
		return "LEDGER_ALREADY_OWNER"
	if not p.sellable or not p.for_sale:
		return "LEDGER_NOT_FOR_SALE"
	if int(me_row.cash) < int(p.price):
		return "LEDGER_NO_MONEY"
	me_row.cash -= int(p.price)
	_transfer(p, me_row, int(p.price))
	return ""


func list_for_sale(actor: int, tunnus: String, price: int) -> String:
	var p := parcel(tunnus)
	if p.is_empty() or int(p.owner_id) != actor:
		return "LEDGER_NOT_OWNER"
	if price <= 0:
		p.for_sale = false
	else:
		p.for_sale = true
		p.price = price
	return ""


func place_bid(actor: int, tunnus: String, amount: int) -> String:
	var p := parcel(tunnus)
	var who: Dictionary = players.get(actor, {})
	if p.is_empty() or who.is_empty():
		return "LEDGER_NO_PARCEL"
	if int(p.owner_id) == 0 or int(p.owner_id) == actor:
		return "LEDGER_NOT_BIDDABLE"
	if amount <= 0 or int(who.cash) < amount:
		return "LEDGER_NO_MONEY"
	for b in bids:
		if b.tunnus == tunnus and b.status == 0 and b.bidder_id == actor:
			b.status = 3
	bids.append({"id": _id(), "tunnus": tunnus, "bidder_id": actor, "bidder_name": who.name, "amount": amount, "placed_month": month,
		"expires_month": month + BID_LIFE_MONTHS, "status": 0})
	_event("bid", "%s bid %d € on %s" % [who.name, amount, p.address], tunnus, actor, amount)
	return ""


func withdraw_bid(actor: int, bid_id: int) -> String:
	for b in bids:
		if b.id == bid_id and b.bidder_id == actor and b.status == 0:
			b.status = 3
			return ""
	return "LEDGER_NO_BID"


func accept_bid(actor: int, bid_id: int) -> String:
	for b in bids:
		if b.id != bid_id:
			continue
		var p := parcel(b.tunnus)
		if p.is_empty() or int(p.owner_id) != actor:
			return "LEDGER_NOT_OWNER"
		if b.status != 0:
			return "LEDGER_NO_BID"
		b.status = 1
		var seller: Dictionary = players[actor]
		if int(b.bidder_id) == 0:
			p.owner_id = 0
			p.owner_name = b.bidder_name
			p.for_sale = true
			p.price = list_price(int(p.land_value))
			seller.cash += int(b.amount)
			_event("sale", "Sold %s (%s) to the %s family" % [p.address, p.tunnus, b.bidder_name], p.tunnus, actor, int(b.amount))
			return ""
		var buyer: Dictionary = players.get(b.bidder_id, {})
		if buyer.is_empty() or int(buyer.cash) < int(b.amount):
			b.status = 2
			return "LEDGER_BIDDER_BROKE"
		buyer.cash -= int(b.amount)
		_transfer(p, buyer, int(b.amount))
		return ""
	return "LEDGER_NO_BID"


func pay_obligation(actor: int, obligation_id: int) -> String:
	for o in obligations:
		if o.id != obligation_id:
			continue
		if o.player_id != actor or o.paid:
			return "LEDGER_NO_OBLIGATION"
		var who: Dictionary = players[actor]
		if int(who.cash) < int(o.amount):
			return "LEDGER_NO_MONEY"
		who.cash -= int(o.amount)
		o.paid = true
		_event("tax", "Paid %d €" % int(o.amount), o.tunnus, actor, -int(o.amount))
		return ""
	return "LEDGER_NO_OBLIGATION"


func build(actor: int, tunnus: String, structure_id: String) -> String:
	var p := parcel(tunnus)
	var s: Dictionary = structures.get(structure_id, {})
	var built: Array = improvements_of(tunnus).map(func(i): return i.structure_id)
	var err := _build_check(actor, p, s, built)
	if err != "":
		return err
	var who: Dictionary = players[actor]
	who.cash -= int(s.cost)
	improvements.append({"id": _id(), "tunnus": tunnus, "structure_id": structure_id, "player_id": actor, "built_month": month})
	_event("build", "%s built %s at %s" % [who.name, structure_id, p.address], tunnus, actor, -int(s.cost))
	return ""


func _build_check(actor: int, p: Dictionary, s: Dictionary, built: Array) -> String:
	if p.is_empty() or int(p.owner_id) != actor:
		return "LEDGER_NOT_OWNER"
	if s.is_empty():
		return "LEDGER_NO_STRUCTURE"
	if s.id in built:
		return "LEDGER_ALREADY_BUILT"
	if s.requires != "" and not (s.requires in built):
		return "LEDGER_REQUIRES"
	if s.purposes.size() > 0 and not (p.purpose in s.purposes):
		return "LEDGER_WRONG_PURPOSE"
	return "LEDGER_NO_MONEY" if int(players[actor].cash) < int(s.cost) else ""


func press_tenant(actor: int, tunnus: String) -> String:
	var p := parcel(tunnus)
	if p.is_empty() or int(p.owner_id) != actor:
		return "LEDGER_NOT_OWNER"
	var total := 0
	for t in tenants_of(tunnus):
		total += int(t.arrears)
		t.arrears = 0
	if total == 0:
		return "LEDGER_NO_ARREARS"
	var who: Dictionary = players[actor]
	who.heat += 2
	who.reputation -= 1
	who.cash += total
	_event("rent", "Collected %d € of arrears at %s" % [total, p.address], tunnus, actor, total)
	return ""


func buy_arrears(actor: int, tunnus: String) -> String:
	var p := parcel(tunnus)
	if p.is_empty():
		return "LEDGER_NO_PARCEL"
	if int(p.owner_id) == actor:
		return "LEDGER_ALREADY_OWNER"
	var total := 0
	for t in tenants_of(tunnus):
		total += int(t.arrears)
	if total == 0:
		return "LEDGER_NO_ARREARS"
	var who: Dictionary = players[actor]
	if int(who.cash) < total:
		return "LEDGER_NO_MONEY"
	for t in tenants_of(tunnus):
		t.arrears = 0
	who.favours += 1
	who.cash -= total
	_event("rent", "%s settled %d € of arrears at %s" % [who.name, total, p.address], tunnus, actor, -total)
	return ""


func donate(actor: int, amount: int) -> String:
	var who: Dictionary = players.get(actor, {})
	if who.is_empty() or amount <= 0 or int(who.cash) < amount:
		return "LEDGER_NO_MONEY"
	who.reputation += int(amount / 1000)
	who.heat = maxi(0, int(who.heat) - 1)
	who.cash -= amount
	_event("tax", "%s donated %d € to the town" % [who.name, amount], "", actor, -amount)
	return ""


func grant(actor: int, amount: int) -> void:
	if players.has(actor):
		players[actor].cash += amount


# ---------------------------------------------------------------- the month

func advance_month() -> void:
	month += 1
	var chance: Dictionary = config.get("arrears_chance", {})
	for tunnus in parcels:
		var p: Dictionary = parcels[tunnus]
		if int(p.owner_id) == 0 or not players.has(p.owner_id):
			continue
		var owner: Dictionary = players[p.owner_id]
		var base := yield_of(tunnus)
		var ts := tenants_of(tunnus)
		var paid := 0
		if ts.is_empty():
			paid = base
		else:
			var share := int(base / ts.size())
			for k in ts.size():
				var t: Dictionary = ts[k]
				var part := share if k < ts.size() - 1 else base - share * (ts.size() - 1)   # the last one carries the remainder
				var c: float = float(chance.get(t.status, chance.get("default", 0.12))) if t.status != "R" else float(chance.get("R", 0.03))
				if rng.randf() < c:
					t.arrears += part
				else:
					paid += part
		if paid > 0:
			owner.cash += paid
			_event("rent", "Rent %d € from %s" % [paid, p.address], tunnus, int(p.owner_id), paid)
		var tax := tax_month(int(p.land_value))
		if tax > 0:
			obligations.append({"id": _id(), "player_id": int(p.owner_id), "kind": "land_tax", "tunnus": tunnus, "amount": tax, "due_month": month + 1, "paid": false})
	var grace := int(config.get("grace_months", 3))
	var penalty := float(config.get("penalty", 0.1))
	for o in obligations:
		if not o.paid and month > int(o.due_month) + grace and players.has(o.player_id):
			var who: Dictionary = players[o.player_id]
			var total := int(o.amount) + int(o.amount * penalty)
			who.heat += 1
			who.cash -= total
			o.paid = true
			_event("tax", "Overdue %s collected with penalty: %d €" % [o.kind, total], o.tunnus, int(o.player_id), -total)
	var drift := int(round(float(config.get("drift", 0.01)) * 1000))
	var roll := rng.randi_range(0, 999)
	price_index = clampi(price_index + int(drift * (roll - 500) / 500), 700, 1500)
	for tunnus in parcels:
		var p: Dictionary = parcels[tunnus]
		if int(p.owner_id) == 0:
			p.price = list_price(int(p.land_value))
	var families: Array = config.get("families", [])
	if families.size() > 0 and rng.randf() < float(config.get("ai_bid_chance", 0.2)):
		var owned := parcels.values().filter(func(p): return int(p.owner_id) != 0)
		if owned.size() > 0:
			var p: Dictionary = owned[rng.randi_range(0, owned.size() - 1)]
			var family: String = families[rng.randi_range(0, families.size() - 1)]
			var amount := int(maxi(int(p.price), int(p.land_value)) * (850 + rng.randi_range(0, 299)) / 1000)
			bids.append({"id": _id(), "tunnus": p.tunnus, "bidder_id": 0, "bidder_name": family, "amount": amount, "placed_month": month,
				"expires_month": month + BID_LIFE_MONTHS, "status": 0})
			_event("bid", "The %s family offers %d € for %s" % [family, amount, p.address], p.tunnus, 0, amount)
	for b in bids:
		if b.status == 0 and int(b.expires_month) <= month:
			b.status = 4
	_event("tick", "Month %d" % month, "", 0, 0)


# ---------------------------------------------------------------- persistence

func to_dict() -> Dictionary:
	var owned := {}
	for tunnus in parcels:
		var p: Dictionary = parcels[tunnus]
		if int(p.owner_id) != 0 or p.for_sale != p.sellable or int(p.price) != list_price(int(p.land_value)):
			owned[tunnus] = {"owner_id": p.owner_id, "owner_name": p.owner_name, "for_sale": p.for_sale, "price": p.price}
	var arrears := {}
	for tunnus in tenants:
		for t in tenants[tunnus]:
			if int(t.arrears) > 0:
				arrears[str(t.registry_code)] = t.arrears
	return {"pack": pack, "month": month, "price_index": price_index, "me_id": me_id, "next_id": _next_id, "rng_state": rng.state,
		"players": players.duplicate(true), "parcels": owned, "arrears": arrears, "bids": bids.duplicate(true),
		"obligations": obligations.duplicate(true), "improvements": improvements.duplicate(true), "events": events.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	month = int(d.get("month", 0))
	price_index = int(d.get("price_index", 1000))
	me_id = int(d.get("me_id", 1))
	_next_id = int(d.get("next_id", _next_id))
	if d.has("rng_state"):
		rng.state = int(d.rng_state)
	players.clear()
	for k in d.get("players", {}):
		var row: Dictionary = d.players[k]
		for f in ["id", "cash", "favours", "heat", "reputation", "joined_month"]:
			row[f] = int(row.get(f, 0))
		players[int(k)] = row
	for tunnus in d.get("parcels", {}):
		if parcels.has(tunnus):
			var o: Dictionary = d.parcels[tunnus]
			parcels[tunnus].owner_id = int(o.get("owner_id", 0))
			parcels[tunnus].owner_name = str(o.get("owner_name", ""))
			parcels[tunnus].for_sale = bool(o.get("for_sale", false))
			parcels[tunnus].price = int(o.get("price", parcels[tunnus].price))
	var arrears: Dictionary = d.get("arrears", {})
	for tunnus in tenants:
		for t in tenants[tunnus]:
			t.arrears = int(arrears.get(str(t.registry_code), 0))
	bids = _ints(d.get("bids", []), ["id", "bidder_id", "amount", "placed_month", "expires_month", "status"])
	obligations = _ints(d.get("obligations", []), ["id", "player_id", "amount", "due_month"])
	improvements = _ints(d.get("improvements", []), ["id", "player_id", "built_month"])
	events = _ints(d.get("events", []), ["id", "month", "actor_id", "amount"])


# ---------------------------------------------------------------- internals

func _transfer(p: Dictionary, buyer: Dictionary, amount: int) -> void:
	if int(p.owner_id) != 0 and players.has(p.owner_id):
		players[p.owner_id].cash += amount
	p.owner_id = int(buyer.id)
	p.owner_name = buyer.name
	p.for_sale = false
	p.price = amount
	for b in bids:
		if b.tunnus == p.tunnus and b.status == 0:
			b.status = 2
	_event("sale", "Sold %s (%s)" % [p.address, p.tunnus], p.tunnus, int(buyer.id), amount)


func _event(kind: String, title: String, tunnus: String, actor: int, amount: int) -> Dictionary:
	var e := {"id": _id(), "month": month, "kind": kind, "title": title, "source": "", "link": "", "tunnus": tunnus, "actor_id": actor,
		"amount": amount, "published": "", "at": Time.get_unix_time_from_system()}
	events.append(e)
	if events.size() > EVENT_KEEP:
		events = events.slice(events.size() - EVENT_KEEP)
	return e


func _id() -> int:
	_next_id += 1
	return _next_id - 1


static func _ints(rows: Array, fields: Array) -> Array:
	for r in rows:
		for f in fields:
			r[f] = int(r.get(f, 0))
	return rows


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}
