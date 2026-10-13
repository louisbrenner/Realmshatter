using System;
using System.Collections.Generic;

namespace Realmshatter;

/// <summary>A unit on the board. Pure data; mutated only by core classes.</summary>
public sealed class Piece
{
	public int Id { get; }
	public int OwnerIndex { get; }
	public CardData Source { get; }
	public PieceStats BaseStats { get; }
	public UnitRole Role { get; }
	public int ApBonus { get; }
	/// <summary>Keyword flags (copied from the card).</summary>
	public Keyword Keywords { get; }

	public GridPos Position { get; internal set; }
	public int CurrentHp { get; internal set; }
	/// <summary>Remaining base shield (does not regenerate). Spell shields are tracked on ActiveSpell.</summary>
	public int CurrentShield { get; internal set; }
	public List<ActiveSpell> ActiveSpells { get; } = new List<ActiveSpell>();
	/// <summary>Temporary statuses (Frozen, Overcharged...). Read-only for views.</summary>
	public List<StatusEffect> StatusEffects { get; } = new List<StatusEffect>();
	/// <summary>True for building pieces (Source.CardType == Building).</summary>
	public bool IsBuilding => Source != null && Source.CardType == CardType.Building;
	/// <summary>Which building this piece is (None for units).</summary>
	public BuildingType Building => Source?.Building ?? BuildingType.None;
	/// <summary>Buildings: still being built (no effect yet). Cleared when it is finished.</summary>
	public bool UnderConstruction { get; internal set; }
	/// <summary>Buildings: global turn at whose start it is finished.</summary>
	public int CompleteTurn { get; internal set; }
	/// <summary>Buildings: id of the unit building it (-1 = none).</summary>
	public int BuilderId { get; internal set; } = -1;
	/// <summary>Builders: id of the unfinished building they work on (-1 = none). They cannot move meanwhile.</summary>
	public int ConstructingId { get; internal set; } = -1;
	/// <summary>Turrets: global turn in which it last fired (once per turn).</summary>
	public int ReactedTurn { get; internal set; } = -1;
	/// <summary>True once the piece has taken damage (its first-hit effect is used up).</summary>
	public bool WasHit { get; internal set; }
	/// <summary>Permanent attack bonus (e.g. from Enrage).</summary>
	public int BonusAttack { get; internal set; }
	/// <summary>Global turn number in which the piece last acted (moved / attacked); -1 = never.</summary>
	public int ActedTurn { get; internal set; } = -1;
	/// <summary>Global turn number in which the piece entered the board.</summary>
	public int SummonedTurn { get; internal set; }

	public bool IsAlive => CurrentHp > 0;

	public Piece(int id, int ownerIndex, CardData source, GridPos position, int summonedTurn = 0)
	{
		SummonedTurn = summonedTurn;
		Id = id;
		OwnerIndex = ownerIndex;
		Source = source;
		BaseStats = PieceStats.FromCard(source);
		Role = source.Role;
		ApBonus = source.ApBonus;
		Keywords = source.Keywords;
		Position = position;
		CurrentHp = Math.Max(1, BaseStats.Hp);
		CurrentShield = Math.Max(0, BaseStats.Shield);
	}

	/// <summary>Deep copy (spells, statuses, acted turn) for state clones / previews.</summary>
	internal Piece(Piece other)
	{
		Id = other.Id;
		OwnerIndex = other.OwnerIndex;
		Source = other.Source;
		BaseStats = other.BaseStats;
		Role = other.Role;
		ApBonus = other.ApBonus;
		Keywords = other.Keywords;
		Position = other.Position;
		CurrentHp = other.CurrentHp;
		CurrentShield = other.CurrentShield;
		SummonedTurn = other.SummonedTurn;
		foreach (ActiveSpell s in other.ActiveSpells)
		{
			ActiveSpells.Add(new ActiveSpell(s.Source, s.Effect, s.CasterIndex, s.CastTurn, s.ExpiryTurn) { RemainingShield = s.RemainingShield });
		}
		foreach (StatusEffect s in other.StatusEffects)
		{
			StatusEffects.Add(new StatusEffect(s.Type, s.AppliedTurn, s.ExpiryTurn, s.SourceName));
		}
		ActedTurn = other.ActedTurn;
		WasHit = other.WasHit;
		BonusAttack = other.BonusAttack;
		UnderConstruction = other.UnderConstruction;
		CompleteTurn = other.CompleteTurn;
		BuilderId = other.BuilderId;
		ConstructingId = other.ConstructingId;
		ReactedTurn = other.ReactedTurn;
	}

	/// <summary>
	/// True while the piece may not receive orders: on the turn it was summoned (it becomes commandable
	/// on its owner's next turn, i.e. any turn after SummonedTurn).
	/// </summary>
	public bool IsSummoningSick(int turnNumber) => turnNumber <= SummonedTurn;

	/// <summary>True if the piece already acted in the given turn (each piece acts once per turn).</summary>
	public bool HasActed(int turnNumber) => ActedTurn == turnNumber;

	/// <summary>True if the piece has all given keyword flags.</summary>
	public bool HasKeyword(Keyword keyword) => keyword != Keyword.None && (Keywords & keyword) == keyword;

	/// <summary>
	/// True if the piece scores VP in the scoring zone: not buildings, not Planted units, and not units that are busy
	/// building (they score again once their building is finished).
	/// </summary>
	public bool CanScore => !IsBuilding && !HasKeyword(Keyword.Planted) && ConstructingId < 0;

	/// <summary>True if the piece currently has the status.</summary>
	public bool HasStatus(StatusEffectType type)
	{
		foreach (StatusEffect s in StatusEffects)
		{
			if (s.Type == type)
			{
				return true;
			}
		}
		return false;
	}

	/// <summary>True while Frozen (effective movement 0).</summary>
	public bool IsFrozen => HasStatus(StatusEffectType.Frozen);

	public int EffectiveMovement => IsFrozen ? 0 : Math.Max(0, BaseStats.Movement + SumDelta(e => e.MovementDelta));
	public int EffectiveAttack => Math.Max(0, BaseStats.Attack + BonusAttack + SumDelta(e => e.AttackDelta));
	/// <summary>Area of its attacks (CardData.AttackArea; Single = a normal attack).</summary>
	public AreaShape AttackArea => Source?.AttackArea ?? AreaShape.Single;

	public int EffectiveRange => Math.Max(0, BaseStats.Range + SumDelta(e => e.RangeDelta));
	public int MaxHp => Math.Max(1, BaseStats.Hp + SumDelta(e => e.HpDelta));

	/// <summary>Base shield remaining plus all remaining spell shields.</summary>
	public int TotalShield
	{
		get
		{
			int total = CurrentShield;
			foreach (ActiveSpell s in ActiveSpells)
			{
				total += s.RemainingShield;
			}
			return total;
		}
	}

	/// <summary>Effective stats including spell modifiers (Hp = current HP, Shield = total shield).</summary>
	public PieceStats EffectiveStats =>
		new PieceStats(EffectiveMovement, EffectiveAttack, CurrentHp, EffectiveRange, TotalShield);

	private int SumDelta(Func<SpellEffect, int> selector)
	{
		int sum = 0;
		foreach (ActiveSpell s in ActiveSpells)
		{
			sum += selector(s.Effect);
		}
		return sum;
	}

	public override string ToString() => $"#{Id} {Source?.Name} (P{OwnerIndex}) at {Position} HP {CurrentHp}/{MaxHp} SHD {TotalShield}";
}
