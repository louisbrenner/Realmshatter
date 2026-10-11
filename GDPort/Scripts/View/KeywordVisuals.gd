class_name KeywordVisuals
extends RefCounted
## Emblem glyph and colors per keyword, shared by the piece tokens (PieceView) and the cards (CardView):
## flame = Burning, snowflake = Frost, fist = Push, spear = Pierce, cross = Mending, bolt = Conduit,
## bell = Echo, skull = Undying.


## Glyph of the keyword emblem (FxIconShape value).
static func get_shape(keyword: int) -> int:
	match keyword:
		Keyword.BURNING: return FxIconShape.FLAME
		Keyword.FROST: return FxIconShape.SNOWFLAKE
		Keyword.PUSH: return FxIconShape.FIST
		Keyword.PIERCE: return FxIconShape.SPEAR
		Keyword.MENDING: return FxIconShape.PLUS
		Keyword.CONDUIT: return FxIconShape.BOLT
		Keyword.ECHO: return FxIconShape.BELL
		Keyword.UNDYING: return FxIconShape.SKULL
	return FxIconShape.PLUS


## Glyph color of the keyword emblem.
static func get_foreground(keyword: int) -> Color:
	match keyword:
		Keyword.BURNING: return Color(1.0, 0.45, 0.08)
		Keyword.FROST: return Color(0.88, 0.97, 1.0)
		Keyword.PUSH: return Color(1.0, 0.86, 0.66)
		Keyword.PIERCE: return Color(0.92, 0.95, 1.0)
		Keyword.MENDING: return Color(0.55, 1.0, 0.55)
		Keyword.CONDUIT: return Color(1.0, 0.93, 0.4)
		Keyword.ECHO: return Color(1.0, 0.83, 0.42)
		Keyword.UNDYING: return Color(0.86, 1.0, 0.94)
	return Color.WHITE


## Coin (background) color of the keyword emblem.
static func get_background(keyword: int) -> Color:
	match keyword:
		Keyword.BURNING: return Color(0.42, 0.08, 0.03, 0.97)
		Keyword.FROST: return Color(0.14, 0.38, 0.72, 0.97)
		Keyword.PUSH: return Color(0.45, 0.26, 0.12, 0.97)
		Keyword.PIERCE: return Color(0.28, 0.33, 0.42, 0.97)
		Keyword.MENDING: return Color(0.1, 0.38, 0.14, 0.97)
		Keyword.CONDUIT: return Color(0.42, 0.3, 0.04, 0.97)
		Keyword.ECHO: return Color(0.46, 0.22, 0.08, 0.97)
		Keyword.UNDYING: return Color(0.16, 0.3, 0.3, 0.97)
	return Color(0.2, 0.2, 0.2, 0.97)
