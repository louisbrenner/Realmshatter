using Godot;

namespace ProjectClaude;

/// <summary>A deck list resource (e.g. Resources/Decks/StarterDeck.tres). Duplicates are listed multiple times.</summary>
[GlobalClass]
public partial class DeckData : Resource
{
	[Export] public string Name { get; set; } = "";
	[Export] public Godot.Collections.Array<CardData> Cards { get; set; } = new Godot.Collections.Array<CardData>();

	/// <summary>Short theme description shown on the deck selection screen.</summary>
	[ExportGroup("Theme")]
	[Export(PropertyHint.MultilineText)] public string Description { get; set; } = "";
	/// <summary>Accent color of the theme (deck selection screen).</summary>
	[Export] public Color AccentColor { get; set; } = new Color(0.98f, 0.79f, 0.38f);
	/// <summary>Signature card shown on the deck selection screen (first card of the list if empty).</summary>
	[Export] public CardData Showcase { get; set; }
}
