namespace Realmshatter;

/// <summary>Effect a unit triggers when it dies (CardData.Deathrattle, strength CardData.DeathrattleAmount).</summary>
public enum DeathrattleType
{
	None,
	/// <summary>Deals Amount damage to every piece next to it - friend or foe.</summary>
	Explode,
	/// <summary>Pushes every piece next to it 1 tile away.</summary>
	Shockwave,
	/// <summary>Its tile and the tiles next to it turn into Lava.</summary>
	LavaPool,
	/// <summary>Heals the owner's pieces within 2 tiles by Amount.</summary>
	HealAllies,
	/// <summary>Raises Walls on the free tiles next to it.</summary>
	RaiseWalls,
	/// <summary>The owner draws Amount cards from its deck.</summary>
	DrawCard,
	/// <summary>Freezes every enemy next to it.</summary>
	FrostNova,
	/// <summary>The owner gains Amount AP at the start of its next turn.</summary>
	Tribute,
}
