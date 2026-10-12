using Godot;

namespace Realmshatter;

/// <summary>
/// Definition of a card. Unit cards use the stat block (Movement..Shield, ApBonus);
/// spell cards use the *Delta modifiers, which are applied to the target piece.
/// ApCost &lt;= 0 means "use the default from GameConfig" (UnitApCost = 1, SpellApCost = 2).
/// </summary>
[GlobalClass]
public partial class CardData : Resource
{
	[ExportGroup("General")]
	[Export] public string Name { get; set; } = "";
	[Export(PropertyHint.MultilineText)] public string Description { get; set; } = "";
	[Export] public CardType CardType { get; set; } = CardType.Unit;
	[Export] public UnitRole Role { get; set; } = UnitRole.Attack;
	/// <summary>Clan of the card (None = basic). Decides the clan deathrattle and the aura effect.</summary>
	[Export] public Clan Clan { get; set; } = Clan.None;
	/// <summary>Rarity (shop price, plate colour). Epic cards are mostly rewards of clan leaders.</summary>
	[Export] public CardRarity Rarity { get; set; } = CardRarity.Common;
	/// <summary>Unit class (Swordsman, Archer...). The card's keywords are the effects layered on top of it.</summary>
	[Export] public UnitClass Class { get; set; } = UnitClass.None;
	[Export] public int ApCost { get; set; } = 0;

	[ExportGroup("Unit Stats")]
	[Export] public int Movement { get; set; } = 2;
	[Export] public int Attack { get; set; } = 1;
	[Export] public int Hp { get; set; } = 3;
	[Export] public int Range { get; set; } = 1;
	[Export] public int Shield { get; set; } = 0;
	[Export] public int ApBonus { get; set; } = 0;

	/// <summary>Keyword flags of a unit (see Keyword / KeywordInfo).</summary>
	[ExportGroup("Keywords")]
	[Export] public Keyword Keywords { get; set; } = Keyword.None;
	/// <summary>Undying upgrade level (0 = original card; each Undying death returns a copy with Level + 1).</summary>
	[Export] public int Level { get; set; } = 0;

	/// <summary>Unique effect of a Legendary unit (see LegendInfo).</summary>
	[ExportGroup("Legendary")]
	[Export] public LegendEffect Legend { get; set; } = LegendEffect.None;

	/// <summary>Effect when the unit dies (see TriggerInfo).</summary>
	[ExportGroup("Triggers")]
	[Export] public DeathrattleType Deathrattle { get; set; } = DeathrattleType.None;
	[Export] public int DeathrattleAmount { get; set; } = 1;
	/// <summary>Effect the first time the unit takes damage and survives.</summary>
	[Export] public FirstHitType OnFirstHit { get; set; } = FirstHitType.None;
	[Export] public int OnFirstHitAmount { get; set; } = 1;

	[ExportGroup("Spell Modifiers")]
	[Export] public int AttackDelta { get; set; } = 0;
	[Export] public int HpDelta { get; set; } = 0;
	[Export] public int ShieldDelta { get; set; } = 0;
	[Export] public int MovementDelta { get; set; } = 0;
	[Export] public int RangeDelta { get; set; } = 0;
	/// <summary>AP the caster gains when the spell resolves (e.g. Mana Surge).</summary>
	[Export] public int ApGain { get; set; } = 0;
	/// <summary>Status granted to the target piece (Piece spells), e.g. Overcharged.</summary>
	[Export] public StatusEffectType GrantStatus { get; set; } = StatusEffectType.None;

	/// <summary>Piece (classic), Tile (single tile) or Area (AreaShape around the clicked tile).</summary>
	[ExportGroup("Spell Targeting")]
	[Export] public SpellTargetType SpellTarget { get; set; } = SpellTargetType.Piece;
	[Export] public AreaShape AreaShape { get; set; } = AreaShape.Single;
	/// <summary>Tile effect placed on every tile of the area (None = no tile effect).</summary>
	[Export] public TileEffectType TileEffect { get; set; } = TileEffectType.None;
	/// <summary>Duration in global turns (2 = until the end of the caster's next turn, like piece spells).</summary>
	[Export] public int TileEffectDuration { get; set; } = 2;
	/// <summary>Immediate damage to every ENEMY piece in the area.</summary>
	[Export] public int SpellDamage { get; set; } = 0;
	/// <summary>Immediate heal to every FRIENDLY piece in the area.</summary>
	[Export] public int SpellHeal { get; set; } = 0;
	/// <summary>Pushes every piece in the area 1 tile away from the anchor (the anchor's piece away from the caster).</summary>
	[Export] public bool SpellPush { get; set; } = false;

	[ExportGroup("Visuals")]
	[Export] public Texture2D Art { get; set; }
	[Export] public Color Tint { get; set; } = Colors.White;

	/// <summary>Building cards only (runtime, see BuildingInfo): which building this piece is.</summary>
	public BuildingType Building { get; set; } = BuildingType.None;

	/// <summary>True if the card has all given keyword flags.</summary>
	public bool HasKeyword(Keyword keyword) => keyword != Keyword.None && (Keywords & keyword) == keyword;

	/// <summary>True for spells cast on a tile (Tile or Area) instead of a piece.</summary>
	public bool TargetsTile => CardType == CardType.Spell && SpellTarget != SpellTargetType.Piece;

	/// <summary>Name without the Undying level suffix (e.g. "Bone Knight" for "Bone Knight +2").</summary>
	public string BaseName
	{
		get
		{
			string suffix = $" +{Level}";
			return Level > 0 && Name.EndsWith(suffix) ? Name[..^suffix.Length] : Name;
		}
	}

	/// <summary>
	/// Returns an upgraded copy for the Undying return: Duplicate() with +1 Attack, +1 Hp, Level + 1 and
	/// the name suffix " +Level". The original resource is never modified.
	/// </summary>
	public CardData CreateUndyingUpgrade()
	{
		string baseName = BaseName;
		CardData copy = Duplicate() as CardData ?? CopyManually();
		copy.Level = Level + 1;
		copy.Attack = Attack + 1;
		copy.Hp = Hp + 1;
		copy.Name = $"{baseName} +{copy.Level}";
		return copy;
	}

	private CardData CopyManually() => new CardData
	{
		Name = Name, Description = Description, CardType = CardType, Role = Role, Clan = Clan, Rarity = Rarity, Class = Class, ApCost = ApCost,
		Movement = Movement, Attack = Attack, Hp = Hp, Range = Range, Shield = Shield, ApBonus = ApBonus,
		Keywords = Keywords, Level = Level, Legend = Legend,
		Deathrattle = Deathrattle, DeathrattleAmount = DeathrattleAmount, OnFirstHit = OnFirstHit, OnFirstHitAmount = OnFirstHitAmount,
		AttackDelta = AttackDelta, HpDelta = HpDelta, ShieldDelta = ShieldDelta, MovementDelta = MovementDelta,
		RangeDelta = RangeDelta, ApGain = ApGain, GrantStatus = GrantStatus,
		SpellTarget = SpellTarget, AreaShape = AreaShape, TileEffect = TileEffect, TileEffectDuration = TileEffectDuration,
		SpellDamage = SpellDamage, SpellHeal = SpellHeal, SpellPush = SpellPush, Art = Art, Tint = Tint,
	};
}
