using Godot;

namespace Realmshatter;

/// <summary>Display names, mottos and colours of the clans.</summary>
public static class ClanInfo
{
	/// <summary>Display name, e.g. "Ember Legion".</summary>
	public static string GetName(Clan clan) => clan switch
	{
		Clan.Fire => "Ember Legion",
		Clan.Healing => "Dawn Covenant",
		Clan.Frost => "Frostbound",
		Clan.Storm => "Storm Circuit",
		Clan.Stone => "Stone Bastion",
		_ => "Townsfolk",
	};

	/// <summary>Main colour of the clan (roofs, banners, name plates).</summary>
	public static Color GetColor(Clan clan) => clan switch
	{
		Clan.Fire => new Color(0.92f, 0.38f, 0.14f),
		Clan.Healing => new Color(0.98f, 0.84f, 0.4f),
		Clan.Frost => new Color(0.5f, 0.82f, 1f),
		Clan.Storm => new Color(0.62f, 0.52f, 1f),
		Clan.Stone => new Color(0.66f, 0.6f, 0.5f),
		_ => new Color(0.75f, 0.7f, 0.62f),
	};
}
