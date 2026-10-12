class_name VendorData
extends Resource
## A merchant in the town: sells its stock and buys any of the player's cards.

@export var id: String = ""
@export var name: String = ""
@export var title: String = "Merchant"
@export_multiline var greeting: String = ""
## Town position in pixels.
@export var position: Vector2
## Awning / clothing colour.
@export var color: Color = Color(0.8, 0.3, 0.25)
@export var stock: Array[CardData] = []
