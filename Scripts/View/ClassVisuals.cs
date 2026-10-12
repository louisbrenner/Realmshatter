namespace Realmshatter;

/// <summary>
/// Picture subject of a card / piece until it has real artwork: one symbol (glyph of icon_glyphs.gdshaderinc) per
/// unit class, building or spell effect. Shared by the card art (card_art.gdshader) and the piece token portraits
/// (piece_portrait.gdshader), so a card and its piece always show the same symbol. -1 = generic role emblem.
/// </summary>
public static class ClassVisuals
{
	/// <summary>Glyph id for the card's picture, or -1 for the role emblem (Swordsman: crossed swords, Guardian: shield).</summary>
	public static int ArtGlyph(CardData card)
	{
		if (card == null)
		{
			return -1;
		}
		if (card.CardType == CardType.Building)
		{
			return card.Building switch
			{
				BuildingType.Turret => (int)FxIconShape.Bow,
				BuildingType.ManaWell => (int)FxIconShape.Gem,
				BuildingType.Shrine => (int)FxIconShape.Plus,
				BuildingType.Barricade => (int)FxIconShape.Bricks,
				BuildingType.Obelisk => (int)FxIconShape.Burst,
				_ => -1,
			};
		}
		if (card.CardType == CardType.Spell)
		{
			if (card.ApGain > 0) return (int)FxIconShape.Gem;
			if (card.GrantStatus == StatusEffectType.Frozen) return (int)FxIconShape.Snowflake;
			if (card.GrantStatus == StatusEffectType.Overcharged) return (int)FxIconShape.Bolt;
			if (card.TileEffect == TileEffectType.Lava) return (int)FxIconShape.Flame;
			if (card.TileEffect == TileEffectType.Wall) return (int)FxIconShape.Bricks;
			if (card.TileEffect == TileEffectType.Healing || card.SpellHeal > 0) return (int)FxIconShape.Plus;
			if (card.SpellDamage > 0) return (int)FxIconShape.Burst;
			if (card.SpellPush) return (int)FxIconShape.Fist;
			int net = card.AttackDelta + card.HpDelta + card.ShieldDelta + card.MovementDelta + card.RangeDelta;
			return net >= 0 ? (int)FxIconShape.Sun : (int)FxIconShape.Skull;
		}
		return card.Class switch
		{
			UnitClass.Archer => (int)FxIconShape.Bow,
			UnitClass.Scout => (int)FxIconShape.Chevrons,
			UnitClass.Lancer => (int)FxIconShape.Spear,
			UnitClass.Mage => (int)FxIconShape.Burst,
			UnitClass.Cleric => (int)FxIconShape.Plus,
			UnitClass.Brute => (int)FxIconShape.Fist,
			UnitClass.Worker => card.ApBonus > 0 ? (int)FxIconShape.Gem : (int)FxIconShape.Hammer,
			UnitClass.Totem => card.ApBonus > 0 ? (int)FxIconShape.Gem
				: (card.HasKeyword(Keyword.Arc) ? (int)FxIconShape.Bolt
				: (card.Deathrattle == DeathrattleType.Explode ? (int)FxIconShape.Burst : (int)FxIconShape.Stake)),
			_ => -1,
		};
	}
}
