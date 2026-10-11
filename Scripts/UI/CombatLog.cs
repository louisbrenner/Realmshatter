using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Collapsible combat log (root of the HUD's LogPanel): a header button toggles the body, lines are
/// colored by who they are about (you = blue, AI = red, turn separators = gold). Keeps the last MaxLines.
/// </summary>
public partial class CombatLog : PanelContainer
{
	[Export] public int MaxLines { get; set; } = 40;
	[Export] public bool StartCollapsed { get; set; }

	private Button _header;
	private RichTextLabel _body;
	private readonly Queue<string> _lines = new Queue<string>();
	private bool _collapsed;
	private int _unread;

	/// <summary>True while only the header is shown.</summary>
	public bool Collapsed => _collapsed;

	public override void _Ready()
	{
		_header = GetNode<Button>("VBox/Header");
		_body = GetNode<RichTextLabel>("VBox/Body");
		_body.BbcodeEnabled = true;
		_body.ScrollFollowing = true;
		_body.Text = "";
		_header.Pressed += () => SetCollapsed(!_collapsed);
		AddThemeStyleboxOverride("panel", HudStyle.WoodPanel(null, 8));
		StyleBoxFlat headerStyle = HudStyle.Box(new Color(0f, 0f, 0f, 0f), new Color(0f, 0f, 0f, 0f), 6, 0, 0);
		StyleBoxFlat headerHover = HudStyle.Box(new Color(1f, 0.85f, 0.5f, 0.08f), new Color(0f, 0f, 0f, 0f), 6, 0, 0);
		_header.AddThemeStyleboxOverride("normal", headerStyle);
		_header.AddThemeStyleboxOverride("hover", headerHover);
		_header.AddThemeStyleboxOverride("pressed", headerHover);
		_header.AddThemeColorOverride("font_color", HudStyle.Gold);
		_header.AddThemeColorOverride("font_hover_color", new Color(1f, 0.9f, 0.6f));
		_header.AddThemeFontSizeOverride("font_size", 15);
		_header.Alignment = HorizontalAlignment.Left;
		_header.FocusMode = FocusModeEnum.None;
		var bodyStyle = HudStyle.Box(new Color(0.05f, 0.03f, 0.015f, 0.55f), new Color(HudStyle.GoldDark, 0.5f), 6, 1, 0);
		bodyStyle.SetContentMarginAll(6);
		_body.AddThemeStyleboxOverride("normal", bodyStyle);
		SetCollapsed(StartCollapsed);
		Rebuild();
	}

	/// <summary>Appends a line (plain text; colored automatically).</summary>
	public void AddLine(string line)
	{
		_lines.Enqueue(Format(line ?? ""));
		while (_lines.Count > MaxLines)
		{
			_lines.Dequeue();
		}
		if (_collapsed)
		{
			_unread++;
			UpdateHeader();
		}
		Rebuild();
	}

	/// <summary>Removes all lines.</summary>
	public void Clear()
	{
		_lines.Clear();
		_unread = 0;
		Rebuild();
		UpdateHeader();
	}

	/// <summary>Collapses (header only) or expands the log.</summary>
	public void SetCollapsed(bool collapsed)
	{
		_collapsed = collapsed;
		if (_body == null)
		{
			return;
		}
		_body.Visible = !collapsed;
		if (!collapsed)
		{
			_unread = 0;
		}
		UpdateHeader();
		Size = new Vector2(Size.X, 0f);
	}

	private void UpdateHeader()
	{
		if (_header == null)
		{
			return;
		}
		string arrow = _collapsed ? "+" : "-";
		_header.Text = _collapsed && _unread > 0 ? $"{arrow}  Combat Log  ({_unread} new)" : $"{arrow}  Combat Log";
	}

	private void Rebuild()
	{
		if (_body == null)
		{
			return;
		}
		_body.Text = _lines.Count == 0 ? "[color=#a08c70][i]Nothing has happened yet.[/i][/color]" : string.Join("\n", _lines);
	}

	private static string Format(string line)
	{
		string text = line.Replace("[", "[lb]");
		if (line.StartsWith("---"))
		{
			return $"[center][color=#f5c860]~ {text.Trim('-', ' ')} ~[/color][/center]";
		}
		string lower = line.ToLowerInvariant();
		if (lower.Contains("wins"))
		{
			return $"[color=#ffd76a]{text}[/color]";
		}
		if (lower.Contains("scored"))
		{
			return $"[color=#f0d080]{text}[/color]";
		}
		if (line.StartsWith("You") || lower.StartsWith("your "))
		{
			return $"[color=#8cc4ff]{text}[/color]";
		}
		if (line.StartsWith("AI"))
		{
			return $"[color=#ff9a8c]{text}[/color]";
		}
		if (lower.Contains("dies"))
		{
			return $"[color=#e0a0a0]{text}[/color]";
		}
		return $"[color=#eadcc0]{text}[/color]";
	}
}
