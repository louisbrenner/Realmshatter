class_name LegendInfo
extends RefCounted
## Names, rule texts, emblem glyphs and colours of the Legendary effects.

## Radius of Dawnlight's heal.
const DAWNLIGHT_RADIUS: int = 3
## Radius of Glacial Grip's freeze.
const GLACIAL_GRIP_RADIUS: int = 2
## How far Chain Lightning reaches and how many enemies it strikes.
const CHAIN_LIGHTNING_RADIUS: int = 5
const CHAIN_LIGHTNING_TARGETS: int = 3
## Damage of Wildfire to each enemy on Lava.
const WILDFIRE_DAMAGE: int = 2


static func display_name(effect: int) -> String:
	match effect:
		LegendEffect.WILDFIRE: return "Wildfire"
		LegendEffect.DAWNLIGHT: return "Dawnlight"
		LegendEffect.GLACIAL_GRIP: return "Glacial Grip"
		LegendEffect.CHAIN_LIGHTNING: return "Chain Lightning"
		LegendEffect.UNBREAKABLE: return "Unbreakable"
	return ""


static func describe(effect: int) -> String:
	match effect:
		LegendEffect.WILDFIRE:
			return "At the start of your turn, every enemy standing on Lava takes %d damage." % WILDFIRE_DAMAGE
		LegendEffect.DAWNLIGHT:
			return "At the start of your turn, your units within %d tiles are healed to full HP." % DAWNLIGHT_RADIUS
		LegendEffect.GLACIAL_GRIP:
			return "At the start of your turn, every enemy within %d tiles is Frozen." % GLACIAL_GRIP_RADIUS
		LegendEffect.CHAIN_LIGHTNING:
			return "At the start of your turn, lightning strikes the %d nearest enemies (within %d tiles) for 1 damage each." % [CHAIN_LIGHTNING_TARGETS, CHAIN_LIGHTNING_RADIUS]
		LegendEffect.UNBREAKABLE:
			return "It takes at most 1 damage from any single hit."
	return ""


## Emblem glyph of the effect (FxIconShape value).
static func get_shape(effect: int) -> int:
	match effect:
		LegendEffect.WILDFIRE: return FxIconShape.FLAME
		LegendEffect.DAWNLIGHT: return FxIconShape.SUN
		LegendEffect.GLACIAL_GRIP: return FxIconShape.SNOWFLAKE
		LegendEffect.CHAIN_LIGHTNING: return FxIconShape.BOLT
		LegendEffect.UNBREAKABLE: return FxIconShape.BRICKS
	return FxIconShape.SUN


## Glyph colour of the effect's emblem (shown on a gold coin).
static func get_color(effect: int) -> Color:
	match effect:
		LegendEffect.WILDFIRE: return Color(1.0, 0.5, 0.12)
		LegendEffect.DAWNLIGHT: return Color(1.0, 0.93, 0.6)
		LegendEffect.GLACIAL_GRIP: return Color(0.8, 0.95, 1.0)
		LegendEffect.CHAIN_LIGHTNING: return Color(0.85, 0.75, 1.0)
		LegendEffect.UNBREAKABLE: return Color(0.9, 0.85, 0.75)
	return Color.WHITE


## Coin colour behind every Legendary emblem.
const EMBLEM_BACKGROUND: Color = Color(0.45, 0.28, 0.04, 0.97)
