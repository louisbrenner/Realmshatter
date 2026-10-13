using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// Opaque "pass the device" screen between two hotseat turns: covers the board and the hand until the next
/// player clicks anywhere (or presses Enter / Space). ShowAsync is awaitable.
/// </summary>
public partial class HotseatCurtain : CanvasLayer
{
	private Control _root;
	private ColorRect _dim;
	private Label _title;
	private Label _subtitle;
	private Button _readyButton;
	private PanelContainer _panel;
	private TaskCompletionSource<bool> _pending;
	/// <summary>Clicks / keys are ignored until this time (ms), so a double-click on End Turn cannot skip the curtain.</summary>
	private ulong _acceptAfterMs;

	/// <summary>Input lock in seconds after the curtain appears.</summary>
	[Export] public float InputDelay { get; set; } = 0.4f;

	public override void _Ready()
	{
		Layer = 20;
		_root = new Control { Name = "Root", Theme = HudStyle.CreateTheme(), MouseFilter = Control.MouseFilterEnum.Stop };
		_root.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
		AddChild(_root);

		_dim = new ColorRect { Color = new Color(0.04f, 0.025f, 0.015f, 0.97f), MouseFilter = Control.MouseFilterEnum.Stop };
		_dim.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
		_root.AddChild(_dim);

		var center = new CenterContainer { MouseFilter = Control.MouseFilterEnum.Ignore };
		center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
		_root.AddChild(center);

		_panel = new PanelContainer { CustomMinimumSize = new Vector2(420, 0) };
		center.AddChild(_panel);
		var box = new VBoxContainer();
		box.AddThemeConstantOverride("separation", 14);
		_panel.AddChild(box);

		_title = new Label { HorizontalAlignment = HorizontalAlignment.Center };
		_title.AddThemeFontSizeOverride("font_size", 34);
		_title.AddThemeConstantOverride("outline_size", 8);
		_title.AddThemeColorOverride("font_outline_color", HudStyle.Outline);
		box.AddChild(_title);

		_subtitle = new Label { HorizontalAlignment = HorizontalAlignment.Center, AutowrapMode = TextServer.AutowrapMode.WordSmart };
		_subtitle.AddThemeFontSizeOverride("font_size", 16);
		_subtitle.AddThemeColorOverride("font_color", HudStyle.TextLight);
		box.AddChild(_subtitle);

		var hint = new Label { Text = "Click anywhere to continue", HorizontalAlignment = HorizontalAlignment.Center };
		hint.AddThemeFontSizeOverride("font_size", 13);
		hint.Modulate = new Color(1f, 1f, 1f, 0.6f);

		_readyButton = new Button { Text = "I'm ready", FocusMode = Control.FocusModeEnum.None, CustomMinimumSize = new Vector2(180, 44) };
		_readyButton.AddThemeFontSizeOverride("font_size", 20);
		_readyButton.SizeFlagsHorizontal = Control.SizeFlags.ShrinkCenter;
		box.AddChild(_readyButton);
		box.AddChild(hint);

		Visible = false;
	}

	/// <summary>Covers the screen with "'title' - 'subtitle'" in the player's accent colour; completes on Ready.</summary>
	public Task ShowAsync(string title, string subtitle, Color accent)
	{
		_pending?.TrySetResult(true);
		_pending = new TaskCompletionSource<bool>();
		_title.Text = title ?? "";
		_title.AddThemeColorOverride("font_color", accent.Lerp(Colors.White, 0.2f));
		_subtitle.Text = subtitle ?? "";
		_panel.AddThemeStyleboxOverride("panel", HudStyle.WoodPanel(accent, 22));
		Visible = true;
		_acceptAfterMs = Time.GetTicksMsec() + (ulong)(Mathf.Max(0f, InputDelay) * 1000f);
		_root.Modulate = new Color(1f, 1f, 1f, 0f);
		CreateTween().TweenProperty(_root, "modulate:a", 1f, 0.25f);
		return _pending.Task;
	}

	/// <summary>Any mouse click (on the button or anywhere else) or Enter / Space closes the curtain.</summary>
	public override void _Input(InputEvent @event)
	{
		if (!Visible)
		{
			return;
		}
		bool click = @event is InputEventMouseButton mouse && mouse.Pressed
			&& (mouse.ButtonIndex == MouseButton.Left || mouse.ButtonIndex == MouseButton.Right);
		bool key = @event is InputEventKey k && k.Pressed && !k.Echo
			&& (k.Keycode == Key.Enter || k.Keycode == Key.KpEnter || k.Keycode == Key.Space);
		if (!click && !key && @event is not InputEventMouseButton)
		{
			return;
		}
		// Swallow every mouse button event (incl. releases) while covered, so nothing reaches the board.
		GetViewport().SetInputAsHandled();
		if ((click || key) && Time.GetTicksMsec() >= _acceptAfterMs)
		{
			Confirm();
		}
	}

	public override void _ExitTree()
	{
		_pending?.TrySetResult(false);
	}

	private void Confirm()
	{
		if (!Visible)
		{
			return;
		}
		Sfx.Play(SfxId.ButtonClick);
		Visible = false;
		TaskCompletionSource<bool> pending = _pending;
		_pending = null;
		pending?.TrySetResult(true);
	}
}
