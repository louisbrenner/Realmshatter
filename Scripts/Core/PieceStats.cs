namespace Realmshatter;

/// <summary>Plain stat block of a piece (base or effective values).</summary>
public struct PieceStats
{
	public int Movement { get; set; }
	public int Attack { get; set; }
	public int Hp { get; set; }
	public int Range { get; set; }
	public int Shield { get; set; }

	public PieceStats(int movement, int attack, int hp, int range, int shield)
	{
		Movement = movement;
		Attack = attack;
		Hp = hp;
		Range = range;
		Shield = shield;
	}

	/// <summary>Reads the unit stat block of a card.</summary>
	public static PieceStats FromCard(CardData card) =>
		new PieceStats(card.Movement, card.Attack, card.Hp, card.Range, card.Shield);

	public override string ToString() => $"MOV {Movement} ATK {Attack} HP {Hp} RNG {Range} SHD {Shield}";
}
