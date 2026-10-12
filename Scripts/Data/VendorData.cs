using Godot;

namespace Realmshatter;

/// <summary>A merchant in the town: sells its stock and buys any of the player's cards.</summary>
[GlobalClass]
public partial class VendorData : Resource
{
	[Export] public string Id { get; set; } = "";
	[Export] public string Name { get; set; } = "";
	[Export] public string Title { get; set; } = "Merchant";
	[Export(PropertyHint.MultilineText)] public string Greeting { get; set; } = "";
	/// <summary>Town position in pixels.</summary>
	[Export] public Vector2 Position { get; set; }
	/// <summary>Awning / clothing colour.</summary>
	[Export] public Color Color { get; set; } = new Color(0.8f, 0.3f, 0.25f);
	[Export] public Godot.Collections.Array<CardData> Stock { get; set; } = new Godot.Collections.Array<CardData>();
}
