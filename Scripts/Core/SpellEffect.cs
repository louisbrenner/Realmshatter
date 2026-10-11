namespace Realmshatter;

/// <summary>Stat modifiers applied by a spell. Values may be negative (debuffs).</summary>
public struct SpellEffect
{
	public int AttackDelta { get; set; }
	public int HpDelta { get; set; }
	public int ShieldDelta { get; set; }
	public int MovementDelta { get; set; }
	public int RangeDelta { get; set; }

	/// <summary>Reads the spell modifiers of a card.</summary>
	public static SpellEffect FromCard(CardData card) => new SpellEffect
	{
		AttackDelta = card.AttackDelta,
		HpDelta = card.HpDelta,
		ShieldDelta = card.ShieldDelta,
		MovementDelta = card.MovementDelta,
		RangeDelta = card.RangeDelta,
	};
}
