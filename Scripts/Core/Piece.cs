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
	/// <summary>Queued order for the current turn, or null.</summary>
	public PieceOrder Order { get; internal set; }
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

	/// <summary>Deep copy (spells, statuses, order) for state clones / previews.</summary>
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
		if (other.Order != null)
		{
			Order = new PieceOrder(other.Order.MoveTarget, other.Order.AttackTarget, other.Order.OrderIndex) { ApPaid = other.Order.ApPaid };
		}
	}

	/// <summary>
	/// True while the piece may not receive orders: on the turn it was summoned (it becomes commandable
	/// on its owner's next turn, i.e. any turn after SummonedTurn).
	/// </summary>
	public bool IsSummoningSick(int turnNumber) => turnNumber <= SummonedTurn;

	/// <summary>True if the piece has all given keyword flags.</summary>
	public bool HasKeyword(Keyword keyword) => keyword != Keyword.None && (Keywords & keyword) == keyword;

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
	public int EffectiveAttack => Math.Max(0, BaseStats.Attack + SumDelta(e => e.AttackDelta));
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
