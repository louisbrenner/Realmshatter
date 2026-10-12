using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Builds the InfoSheets of the hover info panels (InfoPanel): full card rules, pieces on the board (stats,
/// keywords, active spells, statuses), tile effects and deck lists. Texts are kept short; icons and colours carry
/// most of the information (see InfoSheet for the palette).
/// </summary>
public static class InfoText
{
	private static readonly Color TriggerBg = new Color(0.45f, 0.16f, 0.08f, 0.97f);
	private static readonly Color DeathBg = new Color(0.18f, 0.16f, 0.26f, 0.97f);
	private static readonly Color BuildBg = new Color(0.36f, 0.24f, 0.14f, 0.97f);
	private static readonly Color BuffBg = new Color(0.12f, 0.36f, 0.14f, 0.97f);
	private static readonly Color DebuffBg = new Color(0.32f, 0.12f, 0.42f, 0.97f);

	/// <summary>Full rules of a card: type line, AP gem, card text, stat chips and every keyword / effect.</summary>
	public static InfoSheet Card(CardData card, int apCost)
	{
		var sheet = new InfoSheet();
		if (card == null)
		{
			return sheet;
		}
		bool unit = card.CardType == CardType.Unit;
		sheet.Title = card.Name;
		sheet.ApCost = apCost;
		sheet.Subtitle = (unit ? ClassInfo.ClassOrRole(card) : (card.TargetsTile ? "Area spell" : "Spell"))
			+ (card.Clan != Clan.None ? $" · {ClanInfo.GetName(card.Clan)}" : " · Basic");
		sheet.Tag = card.Rarity.ToString();
		sheet.TagColor = CardEconomy.RarityColor(card.Rarity).Lightened(0.2f);
		sheet.Accent = card.Clan != Clan.None ? ClanInfo.GetColor(card.Clan) : HudStyle.GoldDark;
		sheet.Flavor = Esc(card.Description?.Trim() ?? "");

		if (unit)
		{
			AddUnitStats(sheet, card.Attack, card.Attack, card.Hp, card.Hp, card.Hp, card.Shield, card.Movement, card.Movement, card.Range, card.Range);
			if (card.ApBonus != 0)
			{
				sheet.Stats.Add(new InfoSheet.Stat(InfoSheet.StatKind.Ap, $"{Signed(card.ApBonus)}/turn", InfoSheet.GoodColor, "AP for you at the start of each turn"));
			}
		}
		else
		{
			sheet.Lines.AddRange(SpellEffectLines(card));
		}

		AddKeywordRows(sheet, card, card.Keywords, card.Level);
		AddLegendRow(sheet, card);
		AddTriggerRows(sheet, card, false);
		if (!unit && card.TileEffect != TileEffectType.None)
		{
			sheet.Rows.Add(TileRow(card.TileEffect, ""));
		}
		if (!unit && card.GrantStatus != StatusEffectType.None)
		{
			sheet.Rows.Add(StatusRow(card.GrantStatus, ""));
		}
		return sheet;
	}

	/// <summary>Everything about a piece on the board, seen by player 'viewer'.</summary>
	public static InfoSheet Piece(Piece p, GameState state, int viewer)
	{
		var sheet = new InfoSheet();
		if (p == null || state == null)
		{
			return sheet;
		}
		bool mine = p.OwnerIndex == viewer;
		sheet.Title = p.Source?.Name ?? "Piece";
		sheet.TitleColor = mine ? InfoSheet.TextColor : HudStyle.EnemyRed.Lightened(0.1f);
		sheet.Tag = mine ? "Yours" : "Enemy";
		sheet.TagColor = mine ? HudStyle.PlayerBlue.Lightened(0.2f) : HudStyle.EnemyRed;
		// The header shows the card's clan (like the card tooltip); ownership is the tag and the title colour.
		Clan clan = p.Source?.Clan ?? Clan.None;
		sheet.Accent = clan != Clan.None ? ClanInfo.GetColor(clan) : HudStyle.GoldDark;

		if (p.IsBuilding)
		{
			sheet.Subtitle = "Building";
			AddHealth(sheet, p);
			sheet.Lines.Add(BuildingInfo.GetDescription(p.Building));
			if (p.UnderConstruction)
			{
				int left = System.Math.Max(1, (p.CompleteTurn - state.TurnNumber + 1) / 2);
				sheet.Notes.Add($"[color={InfoSheet.HexBad}]Under construction[/color] - ready in {left} turn{(left > 1 ? "s" : "")}. Collapses if its builder dies.");
			}
			return sheet;
		}

		sheet.Subtitle = (p.Source != null ? ClassInfo.ClassOrRole(p.Source) : p.Role.ToString())
			+ (p.Source != null && p.Source.Clan != Clan.None ? $" · {ClanInfo.GetName(p.Source.Clan)}" : "");
		AddUnitStats(sheet, p.EffectiveAttack, p.BaseStats.Attack, p.CurrentHp, p.MaxHp, p.BaseStats.Hp, p.TotalShield,
			p.EffectiveMovement, p.BaseStats.Movement, p.EffectiveRange, p.BaseStats.Range);
		if (p.ApBonus != 0)
		{
			sheet.Stats.Add(new InfoSheet.Stat(InfoSheet.StatKind.Ap, $"{Signed(p.ApBonus)}/turn", InfoSheet.GoodColor, "AP for its owner each turn"));
		}

		AddKeywordRows(sheet, p.Source, p.Keywords, p.Source?.Level ?? 0);
		AddLegendRow(sheet, p.Source);
		AddTriggerRows(sheet, p.Source, p.WasHit);
		if (p.BonusAttack > 0)
		{
			sheet.Rows.Add(new InfoSheet.Row(FxIconShape.Burst, new Color(1f, 0.82f, 0.45f), TriggerBg, "Enraged", InfoSheet.GoodColor,
				$"+{p.BonusAttack} Attack for the rest of the game."));
		}
		foreach (ActiveSpell s in p.ActiveSpells)
		{
			var parts = new List<string>();
			AddDelta(parts, s.Effect.AttackDelta, "Atk");
			AddDelta(parts, s.Effect.HpDelta, "HP");
			if (s.RemainingShield > 0)
			{
				parts.Add($"[color={InfoSheet.HexGood}]{s.RemainingShield} Shield[/color]");
			}
			AddDelta(parts, s.Effect.MovementDelta, "Move");
			AddDelta(parts, s.Effect.RangeDelta, "Range");
			bool friendly = s.CasterIndex == p.OwnerIndex;
			string effect = parts.Count > 0 ? string.Join(", ", parts) : "no stat change";
			sheet.Rows.Add(new InfoSheet.Row(friendly ? FxIconShape.Plus : FxIconShape.Cross,
				friendly ? new Color(0.6f, 1f, 0.55f) : new Color(0.9f, 0.7f, 1f), friendly ? BuffBg : DebuffBg,
				Esc(s.Source?.Name ?? "Spell"), friendly ? InfoSheet.GoodColor : InfoSheet.MagicColor,
				$"{effect} [color={InfoSheet.HexMuted}]({TurnsLeft(s.ExpiryTurn, state.TurnNumber)})[/color]"));
		}
		foreach (StatusEffect s in p.StatusEffects)
		{
			sheet.Rows.Add(StatusRow(s.Type, $" [color={InfoSheet.HexMuted}]({TurnsLeft(s.ExpiryTurn, state.TurnNumber)})[/color]"));
		}

		if (p.IsSummoningSick(state.TurnNumber))
		{
			sheet.Notes.Add($"[color={InfoSheet.HexMuted}]Summoning sick - acts next turn.[/color]");
		}
		else if (mine && p.HasActed(state.TurnNumber))
		{
			sheet.Notes.Add($"[color={InfoSheet.HexMine}]Already acted this turn.[/color]");
		}
		if (p.ConstructingId >= 0)
		{
			sheet.Notes.Add("Busy building - cannot move and scores no VP until the building is finished.");
		}
		if (!p.CanScore)
		{
			if (state.Board.IsInScoringZone(p.Position) && p.HasKeyword(Keyword.Planted))
			{
				sheet.Notes.Add($"[color={InfoSheet.HexMuted}]Planted - scores no VP here.[/color]");
			}
		}
		else if (state.Board.IsInHotZone(p.Position))
		{
			sheet.Notes.Add($"[color={InfoSheet.HexGood}]Crown field: +{state.Board.HotZonePoints} VP[/color] each owner's turn.");
		}
		else if (state.Board.IsInScoringZone(p.Position))
		{
			sheet.Notes.Add($"[color={InfoSheet.HexGood}]Scoring zone: +1 VP[/color] each owner's turn.");
		}
		if (state.Board.GetTerrain(p.Position) == TerrainType.Water)
		{
			sheet.Notes.Add($"[color={InfoSheet.HexMine}]Wading[/color] - every water tile costs {state.Board.WaterMoveCost} movement.");
		}
		TileEffect tile = state.Board.GetTileEffect(p.Position);
		if (tile != null)
		{
			sheet.Notes.Add($"On [b][color={TileHex(tile.Type)}]{KeywordInfo.GetTileEffectName(tile.Type)}[/color][/b] " +
				$"({TurnsLeft(tile.ExpiryTurn, state.TurnNumber)}): {KeywordInfo.GetTileEffectDescription(tile.Type)}");
		}
		return sheet;
	}

	/// <summary>Info about a tile effect on an (empty) tile, the crown field, or an empty sheet.</summary>
	public static InfoSheet Tile(GridPos pos, GameState state, int viewer)
	{
		var sheet = new InfoSheet();
		Trap trap = state?.Board.GetTrap(pos);
		if (trap != null && trap.OwnerIndex == viewer)
		{
			sheet.Title = TrapInfo.GetName(trap.Type);
			sheet.Subtitle = "Your hidden trap";
			sheet.Accent = TrapInfo.GetColor(trap.Type).Darkened(0.35f);
			sheet.Rows.Add(new InfoSheet.Row(FxIconShape.Trap, TrapInfo.GetColor(trap.Type), new Color(0.12f, 0.1f, 0.08f, 0.97f),
				"Springs", InfoSheet.HeadingColor, $"An enemy stepping here is stopped and takes {TrapInfo.Describe(trap.Type)}"));
			return sheet;
		}
		TileEffect tile = state?.Board.GetTileEffect(pos);
		TerrainType terrain = state?.Board.GetTerrain(pos) ?? TerrainType.None;
		if (tile == null && terrain != TerrainType.None)
		{
			AddTerrain(sheet, terrain, pos, state);
			return sheet;
		}
		if (tile == null)
		{
			if (state != null && state.Board.IsInHotZone(pos))
			{
				sheet.Title = "Crown field";
				sheet.Subtitle = "Centre of the scoring zone";
				sheet.Accent = HudStyle.Gold.Darkened(0.2f);
				sheet.Rows.Add(new InfoSheet.Row(FxIconShape.Sun, new Color(1f, 0.92f, 0.55f), new Color(0.4f, 0.32f, 0.08f, 0.97f),
					$"+{state.Board.HotZonePoints} VP", InfoSheet.GoodColor, "per piece here at the start of its owner's turn (1 VP elsewhere in the zone)."));
			}
			return sheet;
		}
		sheet.Title = KeywordInfo.GetTileEffectName(tile.Type);
		string creator = tile.CreatorIndex < 0 ? "neutral" : (tile.CreatorIndex == viewer ? "yours" : "enemy");
		string source = string.IsNullOrEmpty(tile.SourceName) ? "" : $"{tile.SourceName} · ";
		sheet.Subtitle = $"Tile effect · {source}{creator}";
		sheet.Tag = tile.IsPermanent ? "Permanent" : TurnsLeft(tile.ExpiryTurn, state.TurnNumber);
		sheet.TagColor = InfoSheet.MutedColor.Lightened(0.2f);
		sheet.Accent = TileColor(tile.Type);
		sheet.Rows.Add(TileRow(tile.Type, ""));
		if (state.Board.IsInScoringZone(pos))
		{
			sheet.Notes.Add($"[color={InfoSheet.HexGood}]Scoring zone tile.[/color]");
		}
		return sheet;
	}

	/// <summary>Header and rule row of a terrain tile (water, bridge, rock).</summary>
	private static void AddTerrain(InfoSheet sheet, TerrainType terrain, GridPos pos, GameState state)
	{
		switch (terrain)
		{
			case TerrainType.Water:
				sheet.Title = "River";
				sheet.Subtitle = "Terrain";
				sheet.Accent = new Color(0.2f, 0.45f, 0.65f);
				sheet.Rows.Add(new InfoSheet.Row(FxIconShape.Chevrons, new Color(0.7f, 0.9f, 1f), new Color(0.1f, 0.25f, 0.45f, 0.97f),
					"Slow", new Color(0.6f, 0.85f, 1f), $"Entering costs {state.Board.WaterMoveCost} movement instead of 1."));
				break;
			case TerrainType.Bridge:
				sheet.Title = "Bridge";
				sheet.Subtitle = "Terrain";
				sheet.Accent = new Color(0.45f, 0.3f, 0.16f);
				sheet.Lines.Add("Crosses the river at normal speed.");
				break;
			case TerrainType.Rock:
				sheet.Title = "Rock wall";
				sheet.Subtitle = "Terrain";
				sheet.Tag = $"{state.Board.GetTerrainHp(pos)}/{state.Config.RockHp} HP";
				sheet.TagColor = InfoSheet.BadColor;
				sheet.Accent = new Color(0.45f, 0.42f, 0.38f);
				sheet.Rows.Add(new InfoSheet.Row(FxIconShape.Bricks, new Color(0.88f, 0.82f, 0.72f), new Color(0.3f, 0.27f, 0.24f, 0.97f),
					"Breakable", InfoSheet.HeadingColor, "Blocks movement. Attack it (or hit it with damage spells) to break it."));
				break;
		}
		if (state.Board.IsInScoringZone(pos))
		{
			sheet.Notes.Add($"[color={InfoSheet.HexGood}]Scoring zone tile.[/color]");
		}
	}

	/// <summary>Deck description and card list (units and spells with counts).</summary>
	public static InfoSheet Deck(DeckData deck)
	{
		var sheet = new InfoSheet();
		if (deck == null)
		{
			return sheet;
		}
		sheet.Title = deck.Name;
		sheet.Subtitle = $"{deck.Cards.Count} cards";
		sheet.Accent = deck.AccentColor;
		var units = new List<(CardData card, int count)>();
		var spells = new List<(CardData card, int count)>();
		foreach (CardData card in deck.Cards)
		{
			if (card == null)
			{
				continue;
			}
			List<(CardData card, int count)> list = card.CardType == CardType.Unit ? units : spells;
			int index = list.FindIndex(e => e.card == card);
			if (index >= 0)
			{
				list[index] = (card, list[index].count + 1);
			}
			else
			{
				list.Add((card, 1));
			}
		}
		AppendCardList(sheet, "Units", units);
		AppendCardList(sheet, "Spells", spells);
		return sheet;
	}

	/// <summary>Short spell effect lines (BBCode, dark-panel colours).</summary>
	public static List<string> SpellEffectLines(CardData card)
	{
		var lines = new List<string>();
		if (card.TargetsTile)
		{
			var effects = new List<string>();
			if (card.SpellDamage > 0)
			{
				effects.Add($"[color={InfoSheet.HexBad}]{card.SpellDamage} damage[/color] to enemies");
			}
			if (card.SpellHeal > 0)
			{
				effects.Add($"[color={InfoSheet.HexGood}]heals {card.SpellHeal}[/color] your pieces");
			}
			if (card.SpellPush)
			{
				effects.Add("pushes every piece 1 tile outward");
			}
			if (card.TileEffect != TileEffectType.None)
			{
				effects.Add($"leaves [color={TileHex(card.TileEffect)}]{KeywordInfo.GetTileEffectName(card.TileEffect)}[/color] for {card.TileEffectDuration} turns");
			}
			if (card.ApGain > 0)
			{
				effects.Add($"[color={InfoSheet.HexMine}]you gain {card.ApGain} AP[/color]");
			}
			lines.Add($"[b]{Capitalize(AreaText(card))}:[/b] {string.Join("; ", effects)}.");
			return lines;
		}
		var parts = new List<string>();
		AddDelta(parts, card.AttackDelta, "Attack");
		AddDelta(parts, card.HpDelta, "HP");
		AddDelta(parts, card.ShieldDelta, "Shield");
		AddDelta(parts, card.MovementDelta, "Move");
		AddDelta(parts, card.RangeDelta, "Range");
		if (parts.Count > 0)
		{
			lines.Add($"[b]Any piece:[/b] {string.Join(", ", parts)} until the end of your next turn.");
		}
		else if (card.ApGain <= 0)
		{
			lines.Add("[b]Any piece.[/b]");
		}
		if (card.ApGain > 0)
		{
			lines.Add($"[color={InfoSheet.HexMine}]You gain {card.ApGain} AP.[/color]");
		}
		return lines;
	}

	private static void AddUnitStats(InfoSheet sheet, int atk, int baseAtk, int hp, int maxHp, int baseHp, int shield,
		int move, int baseMove, int range, int baseRange)
	{
		// Attack and health are printed on the card / piece badges; the panel shows what they do not.
		if (shield > 0)
		{
			sheet.Stats.Add(new InfoSheet.Stat(InfoSheet.StatKind.Shield, shield.ToString(), InfoSheet.TextColor, "Shield (absorbs damage first)"));
		}
		sheet.Stats.Add(new InfoSheet.Stat(InfoSheet.StatKind.Move, move.ToString(), StatColor(move, baseMove), "Movement"));
		sheet.Stats.Add(new InfoSheet.Stat(InfoSheet.StatKind.Range, range.ToString(), StatColor(range, baseRange), "Attack range"));
	}

	private static void AddHealth(InfoSheet sheet, Piece p)
	{
		if (p.TotalShield > 0)
		{
			sheet.Stats.Add(new InfoSheet.Stat(InfoSheet.StatKind.Shield, p.TotalShield.ToString(), InfoSheet.TextColor, "Shield"));
		}
		if (p.EffectiveAttack > 0)
		{
			sheet.Stats.Add(new InfoSheet.Stat(InfoSheet.StatKind.Range, p.EffectiveRange.ToString(), InfoSheet.TextColor, "Range"));
		}
	}

	private static void AddKeywordRows(InfoSheet sheet, CardData card, Keyword keywords, int level)
	{
		foreach (Keyword k in KeywordInfo.Split(keywords))
		{
			string name = KeywordInfo.GetName(k);
			if (k == Keyword.Undying && level > 0)
			{
				name += $" +{level}";
			}
			Color fg = KeywordVisuals.GetForeground(k);
			Color bg = KeywordVisuals.GetBackground(k);
			if (k == Keyword.Aura && card != null)
			{
				fg = ClanInfo.GetColor(card.Clan).Lightened(0.35f);
				bg = ClanInfo.GetColor(card.Clan).Darkened(0.65f);
			}
			string text = KeywordInfo.GetDescription(k);
			if (k == Keyword.Builder && card != null)
			{
				BuildingType b = BuildingInfo.ForClass(card.Class);
				if (b != BuildingType.None)
				{
					text = $"Builds a [b]{BuildingInfo.GetName(b)}[/b] next to it ({BuildingInfo.GetCost(b)} AP, {BuildingInfo.GetBuildTurns(b)} turn{(BuildingInfo.GetBuildTurns(b) > 1 ? "s" : "")}): " +
						$"{BuildingInfo.GetDescription(b)} [color={InfoSheet.HexMuted}]Cannot move while building.[/color]";
				}
			}
			else if (k == Keyword.Trapper && card != null)
			{
				TrapType trap = TrapInfo.ForClan(card.Clan);
				text = $"Instead of attacking (also after moving), hides a [b]{TrapInfo.GetName(trap)}[/b] on a free tile next to it " +
					$"(1 AP). An enemy stepping on it is stopped and takes {TrapInfo.Describe(trap)} " +
					$"[color={InfoSheet.HexMuted}]Hidden from the enemy, up to 2 at once.[/color]";
			}
			else if (k == Keyword.Aura && card != null)
			{
				name = TriggerInfo.AuraName(card.Clan);
				text = $"Each of your turns it {TriggerInfo.AuraText(card.Clan)}";
			}
			sheet.Rows.Add(new InfoSheet.Row(KeywordVisuals.GetShape(k), fg, bg, name, fg.Lerp(InfoSheet.HeadingColor, 0.5f), text));
		}
	}

	private static void AddLegendRow(InfoSheet sheet, CardData card)
	{
		if (card == null || card.Legend == LegendEffect.None)
		{
			return;
		}
		sheet.Rows.Add(new InfoSheet.Row(LegendInfo.GetShape(card.Legend), LegendInfo.GetColor(card.Legend), LegendInfo.EmblemBackground,
			$"Legendary: {LegendInfo.GetName(card.Legend)}", CardEconomy.RarityColor(CardRarity.Legendary).Lightened(0.2f), LegendInfo.Describe(card.Legend)));
	}

	private static void AddTriggerRows(InfoSheet sheet, CardData card, bool firstHitUsed)
	{
		if (card == null || card.CardType != CardType.Unit)
		{
			return;
		}
		if (card.OnFirstHit != FirstHitType.None)
		{
			string used = firstHitUsed ? $" [color={InfoSheet.HexMuted}](used)[/color]" : "";
			sheet.Rows.Add(new InfoSheet.Row(FxIconShape.Burst, new Color(1f, 0.82f, 0.45f), TriggerBg,
				$"First hit: {TriggerInfo.GetName(card.OnFirstHit)}", InfoSheet.HeadingColor,
				$"{Capitalize(TriggerInfo.Describe(card.OnFirstHit, System.Math.Max(1, card.OnFirstHitAmount)))}{used}"));
		}
		if (card.Deathrattle != DeathrattleType.None)
		{
			sheet.Rows.Add(new InfoSheet.Row(FxIconShape.Tomb, new Color(0.85f, 0.85f, 0.95f), DeathBg,
				$"Deathrattle: {TriggerInfo.GetName(card.Deathrattle)}", new Color(0.82f, 0.8f, 1f),
				Capitalize(TriggerInfo.Describe(card.Deathrattle, System.Math.Max(1, card.DeathrattleAmount)))));
		}
	}

	private static InfoSheet.Row StatusRow(StatusEffectType status, string suffix)
	{
		bool frost = status == StatusEffectType.Frozen;
		return new InfoSheet.Row(frost ? FxIconShape.Snowflake : FxIconShape.Bolt,
			frost ? new Color(0.88f, 0.97f, 1f) : new Color(1f, 0.93f, 0.4f),
			frost ? new Color(0.14f, 0.38f, 0.72f, 0.97f) : new Color(0.42f, 0.3f, 0.04f, 0.97f),
			KeywordInfo.GetStatusName(status), InfoSheet.MagicColor, KeywordInfo.GetStatusDescription(status) + suffix);
	}

	private static InfoSheet.Row TileRow(TileEffectType type, string suffix)
	{
		FxIconShape icon = type switch
		{
			TileEffectType.Lava => FxIconShape.Flame,
			TileEffectType.Healing => FxIconShape.Plus,
			TileEffectType.Ice => FxIconShape.Snowflake,
			TileEffectType.Storm => FxIconShape.Bolt,
			TileEffectType.Mud => FxIconShape.Chevrons,
			TileEffectType.Wall => FxIconShape.Bricks,
			_ => FxIconShape.Bricks,
		};
		Color color = TileColor(type);
		return new InfoSheet.Row(icon, color.Lightened(0.35f), new Color(color.Darkened(0.6f), 0.97f),
			KeywordInfo.GetTileEffectName(type), color.Lightened(0.25f), KeywordInfo.GetTileEffectDescription(type) + suffix);
	}

	private static void AppendCardList(InfoSheet sheet, string title, List<(CardData card, int count)> list)
	{
		if (list.Count == 0)
		{
			return;
		}
		int total = 0;
		foreach ((CardData _, int count) in list)
		{
			total += count;
		}
		var entries = new List<string>();
		foreach ((CardData card, int count) in list)
		{
			entries.Add($"[color={InfoSheet.HexHeading}]{count}x[/color] {Esc(card.Name)}");
		}
		sheet.Lines.Add($"[b][color={InfoSheet.HexHeading}]{title} ({total})[/color][/b]\n{string.Join("\n", entries)}");
	}

	private static string AreaText(CardData card)
	{
		if (card.SpellTarget == SpellTargetType.Tile)
		{
			return "one tile";
		}
		return card.AreaShape switch
		{
			AreaShape.Plus => "cross of 5 tiles",
			AreaShape.Row3 => "row of 3 tiles",
			AreaShape.Column3 => "column of 3 tiles",
			AreaShape.Square2 => "2x2 square",
			_ => "one tile",
		};
	}

	private static string TurnsLeft(int expiryTurn, int currentTurn)
	{
		if (expiryTurn >= TileEffect.Permanent)
		{
			return "permanent";
		}
		int left = System.Math.Max(0, expiryTurn - currentTurn + 1);
		return left <= 1 ? "ends this turn" : $"{left} turns left";
	}

	private static Color TileColor(TileEffectType type) => type switch
	{
		TileEffectType.Lava => new Color(0.95f, 0.38f, 0.1f),
		TileEffectType.Healing => new Color(0.35f, 0.8f, 0.3f),
		TileEffectType.Wall => new Color(0.6f, 0.55f, 0.48f),
		TileEffectType.Ice => new Color(0.55f, 0.82f, 1f),
		TileEffectType.Storm => new Color(0.65f, 0.45f, 1f),
		TileEffectType.Mud => new Color(0.55f, 0.4f, 0.22f),
		_ => new Color(0.55f, 0.48f, 0.42f),
	};

	private static string TileHex(TileEffectType type) => "#" + TileColor(type).Lightened(0.25f).ToHtml(false);

	private static Color StatColor(int value, int baseValue) =>
		value > baseValue ? InfoSheet.GoodColor : (value < baseValue ? InfoSheet.BadColor : InfoSheet.TextColor);

	private static void AddDelta(List<string> parts, int value, string label)
	{
		if (value != 0)
		{
			parts.Add($"[color={(value > 0 ? InfoSheet.HexGood : InfoSheet.HexBad)}]{Signed(value)} {label}[/color]");
		}
	}

	private static string Signed(int value) => value > 0 ? $"+{value}" : value.ToString();

	private static string Capitalize(string text) => string.IsNullOrEmpty(text) ? "" : char.ToUpperInvariant(text[0]) + text[1..];

	private static string Esc(string text) => (text ?? "").Replace("[", "[lb]");
}
