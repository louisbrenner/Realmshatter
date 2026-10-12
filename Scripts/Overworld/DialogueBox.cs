using System;
using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>Parchment dialogue box at the bottom of the screen: speaker name, title, text and answer buttons.</summary>
public partial class DialogueBox : PanelContainer
{
	private Label _name;
	private Label _title;
	private RichTextLabel _text;
	private HBoxContainer _buttons;
	private Tween _tween;

	/// <summary>True while visible.</summary>
	public bool IsOpen => Visible;

	public override void _Ready()
	{
		EnsureBuilt();
	}

	/// <summary>Shows a line with answer options (label + action). Selecting an option runs its action.</summary>
	public void Open(string speaker, Color speakerColor, string title, string text, IReadOnlyList<(string Label, Action Action)> options)
	{
		EnsureBuilt();
		_name.Text = speaker;
		_name.AddThemeColorOverride("font_color", speakerColor);
		_title.Text = title;
		_text.Text = text;
		foreach (Node child in _buttons.GetChildren())
		{
			child.QueueFree();
		}
		foreach ((string label, Action action) in options)
		{
			var button = new Button { Text = label, FocusMode = FocusModeEnum.None, CustomMinimumSize = new Vector2(130, 34) };
			button.AddThemeFontSizeOverride("font_size", 16);
			button.Pressed += () =>
			{
				Sfx.Play(SfxId.ButtonClick);
				action?.Invoke();
			};
			_buttons.AddChild(button);
		}
		if (!Visible)
		{
			Visible = true;
			Modulate = new Color(1, 1, 1, 0);
			_tween?.Kill();
			_tween = CreateTween();
			_tween.TweenProperty(this, "modulate:a", 1f, 0.15f);
			Sfx.Play(SfxId.CardFlip, -4f, 0.8f);
		}
	}

	/// <summary>Hides the box.</summary>
	public void Close()
	{
		Visible = false;
	}

	/// <summary>Runs the first option (keyboard confirm).</summary>
	public void ConfirmFirst()
	{
		if (Visible && _buttons.GetChildCount() > 0 && _buttons.GetChild(0) is Button b)
		{
			b.EmitSignal(BaseButton.SignalName.Pressed);
		}
	}

	private void EnsureBuilt()
	{
		if (_name != null)
		{
			return;
		}
		Visible = false;
		MouseFilter = MouseFilterEnum.Stop;
		StyleBoxFlat style = HudStyle.ParchmentPanel(22, 14);
		style.SetBorderWidthAll(3);
		style.BorderColor = new Color(0.42f, 0.26f, 0.09f);
		style.ShadowSize = 16;
		style.SetCornerRadiusAll(10);
		AddThemeStyleboxOverride("panel", style);

		var box = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		box.AddThemeConstantOverride("separation", 6);
		AddChild(box);
		var header = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		header.AddThemeConstantOverride("separation", 12);
		box.AddChild(header);
		_name = new Label { MouseFilter = MouseFilterEnum.Ignore };
		_name.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		_name.AddThemeFontSizeOverride("font_size", 22);
		_name.AddThemeColorOverride("font_outline_color", new Color(0.12f, 0.07f, 0.03f));
		_name.AddThemeConstantOverride("outline_size", 6);
		header.AddChild(_name);
		_title = new Label { MouseFilter = MouseFilterEnum.Ignore, SizeFlagsVertical = SizeFlags.ShrinkCenter };
		_title.AddThemeFontOverride("font", VfxAssets.CardTextFont);
		_title.AddThemeFontSizeOverride("font_size", 15);
		_title.AddThemeColorOverride("font_color", new Color(0.4f, 0.28f, 0.15f));
		_title.AddThemeConstantOverride("outline_size", 0);
		header.AddChild(_title);

		_text = new RichTextLabel
		{
			BbcodeEnabled = true,
			FitContent = true,
			ScrollActive = false,
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			MouseFilter = MouseFilterEnum.Ignore,
			CustomMinimumSize = new Vector2(640, 0),
		};
		_text.AddThemeFontOverride("normal_font", VfxAssets.CardTextFont);
		_text.AddThemeFontOverride("bold_font", VfxAssets.CardTextBoldFont);
		_text.AddThemeFontSizeOverride("normal_font_size", 17);
		_text.AddThemeFontSizeOverride("bold_font_size", 17);
		_text.AddThemeColorOverride("default_color", HudStyle.Ink);
		_text.AddThemeConstantOverride("outline_size", 0);
		box.AddChild(_text);

		_buttons = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore, Alignment = BoxContainer.AlignmentMode.End };
		_buttons.AddThemeConstantOverride("separation", 10);
		box.AddChild(_buttons);
	}
}
