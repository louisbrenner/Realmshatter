namespace ProjectClaude;

/// <summary>
/// A spell currently affecting a piece. It expires at the END of turn ExpiryTurn
/// (= cast turn + 2, i.e. the end of the caster's next turn).
/// RemainingShield is a temporary shield granted by the spell; it absorbs damage
/// before the piece's own shield and vanishes on expiry.
/// </summary>
public sealed class ActiveSpell
{
	public CardData Source { get; }
	public SpellEffect Effect { get; }
	public int CasterIndex { get; }
	public int CastTurn { get; }
	public int ExpiryTurn { get; }
	public int RemainingShield { get; set; }

	public ActiveSpell(CardData source, SpellEffect effect, int casterIndex, int castTurn, int expiryTurn)
	{
		Source = source;
		Effect = effect;
		CasterIndex = casterIndex;
		CastTurn = castTurn;
		ExpiryTurn = expiryTurn;
		RemainingShield = effect.ShieldDelta > 0 ? effect.ShieldDelta : 0;
	}
}
