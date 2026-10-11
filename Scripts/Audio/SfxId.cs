namespace ProjectClaude;

/// <summary>All procedurally synthesized sound effects (see SfxSynth / Sfx).</summary>
public enum SfxId
{
	// Cards & UI
	CardHover,
	CardPick,
	CardDeal,
	CardFlip,
	ButtonClick,
	EndTurn,
	Coin,
	TurnStart,
	TurnEnemy,
	Victory,
	Defeat,

	// Pieces
	Summon,
	Step,
	Land,
	Blocked,
	Push,
	Swing,
	MeleeHit,
	Shoot,
	ArrowHit,
	Damage,
	ShieldBlock,
	ShieldBreak,
	Death,
	Soul,

	// Rules / spells
	Zap,
	EchoRing,
	Heal,
	Fire,
	LavaBurn,
	Freeze,
	Thaw,
	Charge,
	ChargeRelease,
	WallRise,
	MeteorFall,
	Explosion,
	BuffCast,
	DebuffCast,
	SpellFade,
	TileFade,
}
