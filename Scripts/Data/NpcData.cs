using Godot;

namespace Realmshatter;

/// <summary>A duelist in the town: clan, own deck, dialogue lines, rewards and where it stands.</summary>
[GlobalClass]
public partial class NpcData : Resource
{
	/// <summary>Unique id (used for the "defeated" flags in the save game).</summary>
	[Export] public string Id { get; set; } = "";
	[Export] public string Name { get; set; } = "";
	/// <summary>Rank shown under the name, e.g. "Clan Leader".</summary>
	[Export] public string Title { get; set; } = "";
	[Export] public Clan Clan { get; set; } = Clan.None;
	[Export] public DeckData Deck { get; set; }
	/// <summary>Clan hall the duelist waits in (None = out in the town).</summary>
	[Export] public Clan House { get; set; } = Clan.None;
	/// <summary>Position in pixels: town coordinates, or room coordinates inside its House (HouseInterior).</summary>
	[Export] public Vector2 Position { get; set; }

	[ExportGroup("Dialogue")]
	[Export(PropertyHint.MultilineText)] public string Greeting { get; set; } = "";
	/// <summary>Said when the player wants to battle again after winning.</summary>
	[Export(PropertyHint.MultilineText)] public string RematchLine { get; set; } = "";
	/// <summary>Said after the NPC lost.</summary>
	[Export(PropertyHint.MultilineText)] public string DefeatLine { get; set; } = "";
	/// <summary>Said after the NPC won.</summary>
	[Export(PropertyHint.MultilineText)] public string VictoryLine { get; set; } = "";

	[ExportGroup("Rewards")]
	/// <summary>Gold for the first win (rematch wins pay half, losses a small consolation).</summary>
	[Export] public int RewardGold { get; set; } = 40;
	/// <summary>Cards given on the FIRST win only.</summary>
	[Export] public Godot.Collections.Array<CardData> RewardCards { get; set; } = new Godot.Collections.Array<CardData>();
	/// <summary>On the first win, ONE of these (one the player does not own yet, picked at random) is given as well.</summary>
	[Export] public Godot.Collections.Array<CardData> RewardOneOf { get; set; } = new Godot.Collections.Array<CardData>();

	/// <summary>Extra AP the duelist gets every turn in battle (the endboss plays its expensive legends).</summary>
	[ExportGroup("Battle")]
	[Export] public int BonusApPerTurn { get; set; } = 0;

	/// <summary>Ids of the duelists the player must have beaten before this one accepts a challenge (e.g. the endboss).</summary>
	[ExportGroup("Unlock")]
	[Export] public Godot.Collections.Array<string> RequiresDefeated { get; set; } = new Godot.Collections.Array<string>();
	/// <summary>Said while the duelist is still locked.</summary>
	[Export(PropertyHint.MultilineText)] public string LockedLine { get; set; } = "";
}
