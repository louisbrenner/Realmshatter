class_name DeckData
extends Resource
## A deck list resource (e.g. Resources/Decks/StarterDeck.tres). Duplicates are listed multiple times.

@export var name: String = ""
@export var cards: Array[CardData] = []

## Short theme description shown on the deck selection screen.
@export_group("Theme")
@export_multiline var description: String = ""
## Accent color of the theme (deck selection screen).
@export var accent_color: Color = Color(0.98, 0.79, 0.38)
## Signature card shown on the deck selection screen (first card of the list if empty).
@export var showcase: CardData
