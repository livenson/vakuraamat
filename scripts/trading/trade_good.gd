# One good at one era's trade post. Prices in that era's minor currency unit.
# buy_price: what the player pays to buy it; sell_price: what the post pays. 0 = not offered.
class_name TradeGood
extends Resource

@export var item_id: String
@export var era_id: String
@export var buy_price: int = 0
@export var sell_price: int = 0
