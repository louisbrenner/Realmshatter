using System.Collections.Generic;
using System.Text;
using Godot;

namespace Realmshatter;

/// <summary>
/// Structured content of a hover info panel (InfoPanel): a coloured header (title, type line, owner tag, AP cost),
/// a row of stat chips with icons, rule rows with an emblem icon each (keywords, triggers, statuses, tile effects),
/// and short coloured notes. Built by InfoText; texts may contain BBCode using the Hex* colours below, which are
/// tuned for the dark panel.
/// </summary>
public sealed class InfoSheet
{
	/// <summary>Kind of a stat chip (decides its icon).</summary>
	public enum StatKind
	{
		Attack,
		Health,
		Shield,
		Move,
		Range,
		Ap,
		Turns,
	}

	/// <summary>One stat chip: icon kind, value text and value colour.</summary>
	public readonly record struct Stat(StatKind Kind, string Value, Color Color, string Tooltip = "");

	/// <summary>One rule row: emblem (glyph + colours), coloured title and a short BBCode text.</summary>
	public readonly record struct Row(FxIconShape Icon, Color IconFg, Color IconBg, string Title, Color TitleColor, string Text);

	public static readonly Color TextColor = new Color(1f, 0.93f, 0.8f);
	public static readonly Color MutedColor = new Color(0.78f, 0.66f, 0.5f);
	public static readonly Color GoodColor = new Color(0.55f, 0.95f, 0.45f);
	public static readonly Color BadColor = new Color(1f, 0.48f, 0.4f);
	public static readonly Color HeadingColor = new Color(1f, 0.8f, 0.42f);
	public static readonly Color MagicColor = new Color(0.8f, 0.62f, 1f);

	public static readonly string HexMuted = "#" + MutedColor.ToHtml(false);
	public static readonly string HexGood = "#" + GoodColor.ToHtml(false);
	public static readonly string HexBad = "#" + BadColor.ToHtml(false);
	public static readonly string HexHeading = "#" + HeadingColor.ToHtml(false);
	public static readonly string HexMagic = "#" + MagicColor.ToHtml(false);
	public static readonly string HexMine = "#" + HudStyle.PlayerBlue.Lightened(0.15f).ToHtml(false);
	public static readonly string HexEnemy = "#" + HudStyle.EnemyRed.ToHtml(false);

	public string Title { get; set; } = "";
	/// <summary>Colour of the title (enemy pieces: red).</summary>
	public Color TitleColor { get; set; } = TextColor;
	/// <summary>Muted line under the title (type, class, clan).</summary>
	public string Subtitle { get; set; } = "";
	/// <summary>Small tag on the right of the header, e.g. "Yours" / "Enemy" / rarity.</summary>
	public string Tag { get; set; } = "";
	public Color TagColor { get; set; } = HudStyle.Gold;
	/// <summary>Colour of the header strip (clan, owner or tile effect).</summary>
	public Color Accent { get; set; } = HudStyle.GoldDark;
	/// <summary>AP cost shown as a mana gem in the header (-1 = none).</summary>
	public int ApCost { get; set; } = -1;
	/// <summary>Short italic card text.</summary>
	public string Flavor { get; set; } = "";
	public List<Stat> Stats { get; } = new List<Stat>();
	/// <summary>Free BBCode lines below the stats (spell effects, building rules, deck lists).</summary>
	public List<string> Lines { get; } = new List<string>();
	public List<Row> Rows { get; } = new List<Row>();
	/// <summary>Short BBCode notes at the bottom (state of a piece, scoring, tile under it).</summary>
	public List<string> Notes { get; } = new List<string>();

	/// <summary>True if the sheet has no content.</summary>
	public bool IsEmpty => string.IsNullOrEmpty(Title) && Lines.Count == 0 && Rows.Count == 0 && Notes.Count == 0;

	/// <summary>Content signature, used to skip rebuilding an identical panel.</summary>
	public string Key()
	{
		var sb = new StringBuilder();
		sb.Append(Title).Append(TitleColor).Append('|').Append(Subtitle).Append('|').Append(Tag).Append('|').Append(Accent).Append('|')
			.Append(ApCost).Append('|').Append(Flavor).Append('|');
		foreach (Stat s in Stats)
		{
			sb.Append(s.Kind).Append(s.Value).Append(s.Color).Append(';');
		}
		foreach (string l in Lines)
		{
			sb.Append(l).Append(';');
		}
		foreach (Row r in Rows)
		{
			sb.Append(r.Icon).Append(r.Title).Append(r.Text).Append(';');
		}
		foreach (string n in Notes)
		{
			sb.Append(n).Append(';');
		}
		return sb.ToString();
	}
}
