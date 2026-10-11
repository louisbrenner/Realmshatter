using System.Collections.Generic;
using System.Text;

namespace ProjectClaude;

/// <summary>
/// Builds the BBCode texts of the hover info panels (InfoPanel): full card rules, pieces on the board (stats,
/// keywords, active spells, statuses, order), tile effects and deck lists. Colors are chosen for dark ink on
/// the parchment panel.
/// </summary>
public static class InfoText
{
	private const string Muted = "#6b4a2a";
	private const string Good = "#2f7a22";
	private const string Bad = "#a3261b";
	private const string Mine = "#1f5fa8";
	private const string Enemy = "#b02a1e";
	private const string Heading = "#5a3208";
	private const string Fire = "#c0430c";
	private const string Heal = "#2f7a22";
	private const string Stone = "#5d5246";
	private const string Magic = "#6a35a8";

	/// <summary>Full rules of a card: type line, card text, stats and every keyword / effect explained.</summary>
	public static string Card(CardData card, int apCost)
	{
		if (card == null)
		{
			return "";
		}
		var sb = new StringBuilder();
		sb.Append($"[font_size=18][b]{Esc(card.Name)}[/b][/font_size]\n");
		bool unit = card.CardType == CardType.Unit;
		string type = unit ? $"{card.Role} unit" : (card.TargetsTile ? "Area spell" : "Spell");
		sb.Append($"[color={Muted}]{type}  ·  {apCost} AP[/color]\n");
		if (!string.IsNullOrWhiteSpace(card.Description))
		{
			sb.Append($"[i]{Esc(card.Description.Trim())}[/i]\n");
		}

		if (unit)
		{
			sb.Append($"\n[b]Attack[/b] {card.Attack}   [b]HP[/b] {card.Hp}   [b]Move[/b] {card.Movement}   [b]Range[/b] {card.Range}");
			if (card.Shield > 0)
			{
				sb.Append($"   [b]Shield[/b] {card.Shield}");
			}
			sb.Append('\n');
			if (card.ApBonus != 0)
			{
				sb.Append($"[color={Good}]{Signed(card.ApBonus)} AP at the start of each of your turns while alive.[/color]\n");
			}
		}
		else
		{
			sb.Append('\n');
			foreach (string line in SpellEffectLines(card))
			{
				sb.Append($"• {line}\n");
			}
		}

		AppendKeywordRules(sb, card.Keywords, card.Level);
		if (!unit && card.TileEffect != TileEffectType.None)
		{
			sb.Append($"\n[b][color={TileColor(card.TileEffect)}]{KeywordInfo.GetTileEffectName(card.TileEffect)}[/color][/b]: " +
				$"{KeywordInfo.GetTileEffectDescription(card.TileEffect)}");
		}
		if (!unit && card.GrantStatus != StatusEffectType.None)
		{
			sb.Append($"\n[b][color={Magic}]{KeywordInfo.GetStatusName(card.GrantStatus)}[/color][/b]: " +
				$"{KeywordInfo.GetStatusDescription(card.GrantStatus)}");
		}
		return sb.ToString().TrimEnd('\n');
	}

	/// <summary>Everything about a piece on the board, seen by player 'viewer'.</summary>
	public static string Piece(Piece p, GameState state, int viewer)
	{
		if (p == null || state == null)
		{
			return "";
		}
		var sb = new StringBuilder();
		bool mine = p.OwnerIndex == viewer;
		sb.Append($"[font_size=18][b]{Esc(p.Source?.Name ?? "Piece")}[/b][/font_size]  ");
		sb.Append(mine ? $"[color={Mine}]Yours[/color]\n" : $"[color={Enemy}]Enemy[/color]\n");
		sb.Append($"[color={Muted}]{p.Role} unit[/color]\n\n");

		sb.Append($"[b]HP[/b] {Colored(p.CurrentHp, p.MaxHp, true)}/{Colored(p.MaxHp, p.BaseStats.Hp)}");
		if (p.TotalShield > 0)
		{
			sb.Append($"   [b]Shield[/b] {p.TotalShield}");
		}
		sb.Append($"\n[b]Attack[/b] {Colored(p.EffectiveAttack, p.BaseStats.Attack)}   " +
			$"[b]Move[/b] {Colored(p.EffectiveMovement, p.BaseStats.Movement)}   " +
			$"[b]Range[/b] {Colored(p.EffectiveRange, p.BaseStats.Range)}\n");
		if (p.ApBonus != 0)
		{
			sb.Append($"[color={Good}]{Signed(p.ApBonus)} AP per turn for its owner.[/color]\n");
		}

		AppendKeywordRules(sb, p.Keywords, p.Source?.Level ?? 0);

		if (p.ActiveSpells.Count > 0)
		{
			sb.Append($"\n[b][color={Heading}]Active spells[/color][/b]");
			foreach (ActiveSpell s in p.ActiveSpells)
			{
				var parts = new List<string>();
				AddDelta(parts, s.Effect.AttackDelta, "Attack");
				AddDelta(parts, s.Effect.HpDelta, "HP");
				if (s.RemainingShield > 0)
				{
					parts.Add($"{s.RemainingShield} Shield");
				}
				AddDelta(parts, s.Effect.MovementDelta, "Move");
				AddDelta(parts, s.Effect.RangeDelta, "Range");
				string effect = parts.Count > 0 ? string.Join(", ", parts) : "no stat change";
				string by = s.CasterIndex == viewer ? "your" : "enemy";
				sb.Append($"\n• [b]{Esc(s.Source?.Name ?? "Spell")}[/b] ({by}): {effect} - {TurnsLeft(s.ExpiryTurn, state.TurnNumber)}");
			}
			sb.Append('\n');
		}

		if (p.StatusEffects.Count > 0)
		{
			sb.Append($"\n[b][color={Heading}]Status[/color][/b]");
			foreach (StatusEffect s in p.StatusEffects)
			{
				string from = string.IsNullOrEmpty(s.SourceName) ? "" : $" (from {Esc(s.SourceName)})";
				sb.Append($"\n• [b][color={Magic}]{KeywordInfo.GetStatusName(s.Type)}[/color][/b]{from}: " +
					$"{KeywordInfo.GetStatusDescription(s.Type)} - {TurnsLeft(s.ExpiryTurn, state.TurnNumber)}");
			}
			sb.Append('\n');
		}

		var notes = new List<string>();
		if (p.IsSummoningSick(state.TurnNumber))
		{
			notes.Add("Summoning sick: can receive orders next turn.");
		}
		if (mine && p.Order != null)
		{
			notes.Add(DescribeOrder(p, state));
		}
		if (state.Board.IsInScoringZone(p.Position))
		{
			notes.Add($"[color={Good}]In the scoring zone: +1 VP at the start of its owner's turn.[/color]");
		}
		TileEffect tile = state.Board.GetTileEffect(p.Position);
		if (tile != null)
		{
			notes.Add($"Standing on [b][color={TileColor(tile.Type)}]{KeywordInfo.GetTileEffectName(tile.Type)}[/color][/b] " +
				$"({TurnsLeft(tile.ExpiryTurn, state.TurnNumber)}): {KeywordInfo.GetTileEffectDescription(tile.Type)}");
		}
		if (notes.Count > 0)
		{
			sb.Append('\n');
			foreach (string n in notes)
			{
				sb.Append($"{n}\n");
			}
		}
		return sb.ToString().TrimEnd('\n');
	}

	/// <summary>Info about a tile effect on an (empty) tile, or "" if there is none.</summary>
	public static string Tile(GridPos pos, GameState state, int viewer)
	{
		TileEffect tile = state?.Board.GetTileEffect(pos);
		if (tile == null)
		{
			return "";
		}
		var sb = new StringBuilder();
		sb.Append($"[font_size=18][b][color={TileColor(tile.Type)}]{KeywordInfo.GetTileEffectName(tile.Type)}[/color][/b][/font_size]\n");
		string creator = tile.CreatorIndex < 0 ? "neutral" : (tile.CreatorIndex == viewer ? "yours" : "enemy");
		string source = string.IsNullOrEmpty(tile.SourceName) ? "" : $"{Esc(tile.SourceName)}, ";
		sb.Append($"[color={Muted}]Tile effect ({source}{creator})[/color]\n\n");
		sb.Append(KeywordInfo.GetTileEffectDescription(tile.Type));
		sb.Append($"\n[b]{TurnsLeft(tile.ExpiryTurn, state.TurnNumber)}[/b]");
		if (state.Board.IsInScoringZone(pos))
		{
			sb.Append($"\n\n[color={Good}]Scoring zone tile.[/color]");
		}
		return sb.ToString();
	}

	/// <summary>Deck description and card list (units and spells with counts).</summary>
	public static string Deck(DeckData deck)
	{
		if (deck == null)
		{
			return "";
		}
		var sb = new StringBuilder();
		sb.Append($"[font_size=18][b]{Esc(deck.Name)}[/b][/font_size]\n");
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
		AppendCardList(sb, "Units", units);
		AppendCardList(sb, "Spells", spells);
		return sb.ToString().TrimEnd('\n');
	}

	/// <summary>Short spell effect lines (shared by the info panel and the card face).</summary>
	public static List<string> SpellEffectLines(CardData card)
	{
		var lines = new List<string>();
		if (card.TargetsTile)
		{
			lines.Add($"Target: {AreaText(card)}.");
			if (card.SpellDamage > 0)
			{
				lines.Add($"[color={Bad}]{card.SpellDamage} damage[/color] to every enemy there.");
			}
			if (card.SpellHeal > 0)
			{
				lines.Add($"[color={Good}]Heals {card.SpellHeal} HP[/color] to each of your pieces there.");
			}
			if (card.TileEffect != TileEffectType.None)
			{
				string free = card.TileEffect == TileEffectType.Wall ? " free" : "";
				lines.Add($"Turns the{free} tiles into [color={TileColor(card.TileEffect)}]{KeywordInfo.GetTileEffectName(card.TileEffect)}[/color] " +
					$"for {card.TileEffectDuration} turns.");
			}
			return lines;
		}
		var parts = new List<string>();
		AddDelta(parts, card.AttackDelta, "Attack");
		AddDelta(parts, card.HpDelta, "HP");
		AddDelta(parts, card.ShieldDelta, "Shield");
		AddDelta(parts, card.MovementDelta, "Move");
		AddDelta(parts, card.RangeDelta, "Range");
		lines.Add("Target: any piece.");
		if (parts.Count > 0)
		{
			lines.Add($"{string.Join(", ", parts)} until the end of your next turn.");
		}
		if (card.GrantStatus != StatusEffectType.None)
		{
			lines.Add($"Makes it [color={Magic}]{KeywordInfo.GetStatusName(card.GrantStatus)}[/color].");
		}
		return lines;
	}

	private static void AppendCardList(StringBuilder sb, string title, List<(CardData card, int count)> list)
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
		sb.Append($"\n[b][color={Heading}]{title} ({total})[/color][/b]\n");
		foreach ((CardData card, int count) in list)
		{
			string keywords = card.Keywords != Keyword.None ? $" [color={Muted}]- {KeywordInfo.Format(card.Keywords)}[/color]" : "";
			sb.Append($"{count}x {Esc(card.Name)}{keywords}\n");
		}
	}

	private static void AppendKeywordRules(StringBuilder sb, Keyword keywords, int level)
	{
		List<Keyword> list = KeywordInfo.Split(keywords);
		if (list.Count == 0)
		{
			return;
		}
		sb.Append('\n');
		foreach (Keyword k in list)
		{
			string name = KeywordInfo.GetName(k);
			if (k == Keyword.Undying && level > 0)
			{
				name += $" +{level}";
			}
			sb.Append($"[b][color={Heading}]{name}[/color][/b]: {KeywordInfo.GetDescription(k)}\n");
		}
	}

	private static string DescribeOrder(Piece p, GameState state)
	{
		var parts = new List<string>();
		if (p.Order.MoveTarget.HasValue && p.Order.MoveTarget.Value != p.Position)
		{
			parts.Add($"move to {p.Order.MoveTarget.Value}");
		}
		if (p.Order.AttackTarget.HasValue)
		{
			Piece target = state.Board.GetPieceAt(p.Order.AttackTarget.Value);
			parts.Add(target != null && target.OwnerIndex == p.OwnerIndex && target != p
				? $"chain via {Esc(target.Source?.Name ?? "piece")}"
				: $"attack {p.Order.AttackTarget.Value}");
		}
		string text = parts.Count > 0 ? string.Join(", ", parts) : "hold position";
		return $"[color={Mine}]Order {p.Order.OrderIndex + 1}: {text}.[/color]";
	}

	private static string AreaText(CardData card)
	{
		if (card.SpellTarget == SpellTargetType.Tile)
		{
			return "one tile";
		}
		return card.AreaShape switch
		{
			AreaShape.Plus => "a cross of 5 tiles",
			AreaShape.Row3 => "a row of 3 tiles",
			AreaShape.Column3 => "a column of 3 tiles",
			AreaShape.Square2 => "a 2x2 square",
			_ => "one tile",
		};
	}

	private static string TurnsLeft(int expiryTurn, int currentTurn)
	{
		int left = System.Math.Max(0, expiryTurn - currentTurn + 1);
		return left <= 1 ? "ends this turn" : $"{left} more turns";
	}

	private static string TileColor(TileEffectType type) => type switch
	{
		TileEffectType.Lava => Fire,
		TileEffectType.Healing => Heal,
		TileEffectType.Wall => Stone,
		_ => Magic,
	};

	private static string Colored(int value, int baseValue, bool hp = false)
	{
		if (hp)
		{
			return value < baseValue ? $"[color={Bad}]{value}[/color]" : value.ToString();
		}
		if (value > baseValue)
		{
			return $"[color={Good}]{value}[/color]";
		}
		return value < baseValue ? $"[color={Bad}]{value}[/color]" : value.ToString();
	}

	private static void AddDelta(List<string> parts, int value, string label)
	{
		if (value != 0)
		{
			parts.Add($"[color={(value > 0 ? Good : Bad)}]{Signed(value)} {label}[/color]");
		}
	}

	private static string Signed(int value) => value > 0 ? $"+{value}" : value.ToString();

	private static string Esc(string text) => (text ?? "").Replace("[", "[lb]");
}
