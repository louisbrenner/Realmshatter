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

	/// <summary>The card's modifiers, each pushed 'power' further in its direction (Obelisk: +2 Attack -> +3, -1 -> -2).</summary>
	public static SpellEffect FromCard(CardData card, int power) => new SpellEffect
	{
		AttackDelta = Boost(card.AttackDelta, power),
		HpDelta = Boost(card.HpDelta, power),
		ShieldDelta = Boost(card.ShieldDelta, power),
		MovementDelta = Boost(card.MovementDelta, power),
		RangeDelta = Boost(card.RangeDelta, power),
	};

	/// <summary>Moves a non-zero value 'power' further away from zero (zero stays zero).</summary>
	public static int Boost(int value, int power) => value > 0 ? value + power : (value < 0 ? value - power : 0);
}
