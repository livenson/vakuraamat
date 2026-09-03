# Autoload "Trading": era-scoped wallets and the trade-good registry.
# Hard rule (plan Phase 4): money and goods never cross an era boundary. The wallet is a
# per-era dictionary, and a post only ever touches Inventory's bucket for its own era.
extends Node

const DIR := "res://data/trade_goods/"
const CURRENCY := {"era_1798": "CUR_1798", "era_1938": "CUR_1938", "era_2026": "CUR_2026"}

var goods: Array[TradeGood] = []
var money: Dictionary = {}          # era_id -> int


func _ready() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".tres"):
				goods.append(load(DIR + f))


func goods_for(era_id: String) -> Array:
	return goods.filter(func(g): return g.era_id == era_id)


func balance(era_id: String) -> int:
	return int(money.get(era_id, 0))


func currency_key(era_id: String) -> String:
	return CURRENCY.get(era_id, "CUR_1938")


func format_money(amount: int, era_id: String) -> String:
	return "%d %s" % [amount, tr(currency_key(era_id))]


func add_money(era_id: String, amount: int) -> void:
	money[era_id] = balance(era_id) + amount
	SaveManager.mark_dirty()


## Player buys one unit. Returns false if unaffordable or the good is not sold here.
func buy(g: TradeGood, era_id: String) -> bool:
	if g.era_id != era_id or g.buy_price <= 0 or balance(era_id) < g.buy_price:
		return false
	var item := GameState.item(g.item_id)
	if item == null or item is ArtifactItem:
		push_error("trade post cannot sell %s" % g.item_id)
		return false
	add_money(era_id, -g.buy_price)
	Inventory.add(g.item_id)
	return true


## Player sells one unit from this era's bucket.
func sell(g: TradeGood, era_id: String) -> bool:
	if g.era_id != era_id or g.sell_price <= 0 or GameState.current_era != era_id:
		return false
	if not Inventory.local_items(era_id).has(g.item_id):
		return false
	Inventory.remove(g.item_id)
	add_money(era_id, g.sell_price)
	return true


func to_dict() -> Dictionary:
	return {"money": money.duplicate()}


func from_dict(d: Dictionary) -> void:
	money = d.get("money", {}).duplicate()
	for k in money:
		money[k] = int(money[k])
