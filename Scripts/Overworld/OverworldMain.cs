using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Root of Scenes/Overworld.tscn. Builds the town (TownMap), the duelists and vendors from data, the player with a
/// following camera and the UI. Handles talking (E / Space / Enter or click), entering and leaving the clan halls
/// (walk into a door or press E; inside wait three duelists and the clan leader, see HouseInterior), starting
/// battles (BattleSession + scene change to the battle), the shop and the deck builder (Tab), and greets the player
/// after a battle - back in the hall or town they left.
/// </summary>
public partial class OverworldMain : Node2D
{
	[Export] public Godot.Collections.Array<NpcData> Npcs { get; set; } = new Godot.Collections.Array<NpcData>();
	[Export] public Godot.Collections.Array<VendorData> Vendors { get; set; } = new Godot.Collections.Array<VendorData>();
	[Export] public Vector2 PlayerStart { get; set; } = new Vector2(960, 780);
	[Export] public float TalkDistance { get; set; } = 70f;
	[Export] public float DoorDistance { get; set; } = 40f;
	[Export] public float CameraZoom { get; set; } = 1.35f;

	private static readonly Color TownClearColor = new Color(0.2f, 0.32f, 0.16f);
	private static readonly Color HallClearColor = new Color(0.08f, 0.05f, 0.03f);
	private const float FadeTime = 0.22f;

	private TownMap _map;
	private Node2D _world;
	private OverworldPlayer _player;
	private Camera2D _camera;
	private OverworldUi _ui;
	private HouseInterior _interior;
	private readonly List<OverworldNpc> _townPeople = new List<OverworldNpc>();
	private readonly List<OverworldNpc> _hallPeople = new List<OverworldNpc>();
	private OverworldNpc _nearest;
	private Clan _house = Clan.None;
	private Clan _nearDoor = Clan.None;
	private bool _nearExit;
	private bool _transitioning;

	/// <summary>People of the area the player is in (town or the current hall).</summary>
	private List<OverworldNpc> ActivePeople => _house == Clan.None ? _townPeople : _hallPeople;

	public override void _Ready()
	{
		PlayerProfile.EnsureLoaded();
		AddChild(new Sfx { Name = "Sfx" });
		RenderingServer.SetDefaultClearColor(TownClearColor);

		_map = new TownMap { Name = "Town" };
		foreach (VendorData v in Vendors)
		{
			if (v != null)
			{
				_map.AddStall(v.Position, v.Color);
			}
		}
		foreach (NpcData npc in Npcs)
		{
			if (npc != null && npc.House == Clan.None)
			{
				_map.ReserveSpot(npc.Position);
			}
		}
		AddChild(_map);

		_world = new Node2D { Name = "World", YSortEnabled = true };
		AddChild(_world);
		foreach (NpcData npc in Npcs)
		{
			if (npc == null || npc.House != Clan.None)
			{
				continue;
			}
			var person = new OverworldNpc();
			person.SetupNpc(npc);
			_world.AddChild(person);
			_townPeople.Add(person);
		}
		foreach (VendorData vendor in Vendors)
		{
			if (vendor == null)
			{
				continue;
			}
			var person = new OverworldNpc();
			person.SetupVendor(vendor);
			_world.AddChild(person);
			_townPeople.Add(person);
		}

		_player = new OverworldPlayer { Name = "Player", Position = PlayerStart };
		_world.AddChild(_player);
		_camera = new Camera2D
		{
			Zoom = new Vector2(CameraZoom, CameraZoom),
			PositionSmoothingEnabled = true,
			PositionSmoothingSpeed = 8f,
		};
		_player.AddChild(_camera);
		_camera.MakeCurrent();
		SetCameraLimits(new Rect2(Vector2.Zero, TownMap.MapSize));

		_ui = new OverworldUi { Name = "UI" };
		AddChild(_ui);
		_ui.DeckButtonPressed += OpenDeckBuilder;
		_ui.Shop.Closed += () => _player.InputEnabled = true;
		_ui.DeckBuilder.Closed += () => _player.InputEnabled = true;

		UpdateHouseProgress();
		Clan returnHouse = BattleSession.ReturnHouse;
		if (returnHouse != Clan.None)
		{
			ShowHall(returnHouse, BattleSession.ReturnPosition);
		}
		else if (BattleSession.ReturnPosition is Vector2 back)
		{
			_player.Position = back;
		}
		_camera.ResetSmoothing();
		Callable.From(GreetAfterBattle).CallDeferred();
	}

	public override void _Process(double delta)
	{
		OverworldNpc nearest = null;
		float best = TalkDistance;
		foreach (OverworldNpc p in ActivePeople)
		{
			float d = p.GlobalPosition.DistanceTo(_player.GlobalPosition);
			if (d < best)
			{
				best = d;
				nearest = p;
			}
		}
		if (nearest != _nearest)
		{
			if (_nearest != null)
			{
				_nearest.Highlighted = false;
			}
			_nearest = nearest;
			if (_nearest != null)
			{
				_nearest.Highlighted = true;
			}
		}

		_nearDoor = Clan.None;
		_nearExit = false;
		if (_house == Clan.None)
		{
			foreach (TownMap.House h in _map.Houses)
			{
				if (TownMap.DoorOf(h).DistanceTo(_player.GlobalPosition) < DoorDistance)
				{
					_nearDoor = h.Clan;
				}
			}
			_map.HighlightedDoor = _nearDoor;
		}
		else
		{
			_nearExit = _interior.IsInDoorway(_player.GlobalPosition);
		}

		bool busy = _ui.IsBusy || _transitioning;
		_player.InputEnabled = !busy;
		if (!busy && _nearest == null)
		{
			// Walking into a door enters the hall; walking down out of the doorway leaves it.
			if (_nearDoor != Clan.None && IsHeld("ui_up", Key.W))
			{
				EnterHall(_nearDoor);
			}
			else if (_nearExit && IsHeld("ui_down", Key.S))
			{
				LeaveHall();
			}
		}

		string prompt = "";
		if (_nearest != null)
		{
			prompt = $"E: {(_nearest.Vendor != null ? "Trade with" : "Talk to")} {_nearest.DisplayName}";
		}
		else if (_nearDoor != Clan.None)
		{
			prompt = $"E: Enter the hall of the {ClanInfo.GetName(_nearDoor)}";
		}
		else if (_nearExit)
		{
			prompt = "E: Leave the hall";
		}
		_ui.SetPrompt(_transitioning ? "" : prompt);
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		if (_transitioning)
		{
			return;
		}
		if (@event is InputEventKey key && key.Pressed && !key.Echo)
		{
			switch (key.Keycode)
			{
				case Key.E:
				case Key.Space:
				case Key.Enter:
				case Key.KpEnter:
					if (_ui.Dialogue.IsOpen)
					{
						_ui.Dialogue.ConfirmFirst();
					}
					else if (!_ui.IsBusy && _nearest != null)
					{
						Talk(_nearest);
					}
					else if (!_ui.IsBusy && _nearDoor != Clan.None)
					{
						EnterHall(_nearDoor);
					}
					else if (!_ui.IsBusy && _nearExit)
					{
						LeaveHall();
					}
					GetViewport().SetInputAsHandled();
					break;
				case Key.Tab:
				case Key.B:
					if (_ui.DeckBuilder.IsOpen)
					{
						_ui.DeckBuilder.Close();
					}
					else if (!_ui.IsBusy)
					{
						OpenDeckBuilder();
					}
					GetViewport().SetInputAsHandled();
					break;
				case Key.Escape:
					if (_ui.Dialogue.IsOpen)
					{
						EndTalk();
					}
					else if (_ui.Shop.IsOpen)
					{
						_ui.Shop.Close();
					}
					else if (_ui.DeckBuilder.IsOpen)
					{
						_ui.DeckBuilder.Close();
					}
					GetViewport().SetInputAsHandled();
					break;
			}
		}
		else if (@event is InputEventMouseButton mouse && mouse.Pressed && mouse.ButtonIndex == MouseButton.Left && !_ui.IsBusy)
		{
			Vector2 world = GetGlobalMousePosition();
			foreach (OverworldNpc p in ActivePeople)
			{
				if (p.GlobalPosition.DistanceTo(world + new Vector2(0, 20)) < 30f)
				{
					if (p.GlobalPosition.DistanceTo(_player.GlobalPosition) <= TalkDistance * 1.6f)
					{
						Talk(p);
					}
					else
					{
						_ui.ShowToast($"Walk closer to {p.DisplayName} to talk.", 2f);
					}
					GetViewport().SetInputAsHandled();
					return;
				}
			}
		}
	}

	private static bool IsHeld(string action, Key key) => Input.IsActionPressed(action) || Input.IsPhysicalKeyPressed(key);

	private void SetCameraLimits(Rect2 area)
	{
		_camera.LimitLeft = (int)area.Position.X;
		_camera.LimitTop = (int)area.Position.Y;
		_camera.LimitRight = (int)area.End.X;
		_camera.LimitBottom = (int)area.End.Y;
	}

	// ------------------------------------------------------------------ halls

	/// <summary>Fades out, swaps the town for the clan's hall and fades back in.</summary>
	private void EnterHall(Clan clan)
	{
		if (_transitioning || _house != Clan.None)
		{
			return;
		}
		Sfx.Play(SfxId.ButtonClick);
		FadeSwap(() =>
		{
			ShowHall(clan, null);
			NpcData leader = FindLeader(clan);
			string goal = leader == null ? ""
				: PlayerProfile.HasDefeated(leader.Id) ? $" You have beaten {leader.Name} - rematches are always welcome."
				: $" Beat its three duelists to challenge {leader.Name}.";
			_ui.ShowToast($"Hall of the {ClanInfo.GetName(clan)}.{goal}", 4f);
		});
	}

	/// <summary>Fades out and returns to the town in front of the hall's door.</summary>
	private void LeaveHall()
	{
		if (_transitioning || _house == Clan.None)
		{
			return;
		}
		Sfx.Play(SfxId.ButtonClick);
		FadeSwap(ShowTown);
	}

	private void FadeSwap(System.Action swap)
	{
		_transitioning = true;
		_player.InputEnabled = false;
		EndTalk();
		Tween fade = CreateTween();
		fade.TweenProperty(this, "modulate", new Color(0.05f, 0.05f, 0.05f), FadeTime);
		fade.TweenCallback(Callable.From(() =>
		{
			swap();
			_camera.ResetSmoothing();
		}));
		fade.TweenProperty(this, "modulate", Colors.White, FadeTime);
		fade.TweenCallback(Callable.From(() => _transitioning = false));
	}

	/// <summary>Builds the clan's hall with its duelists and puts the player at the door (or at a given position).</summary>
	private void ShowHall(Clan clan, Vector2? at)
	{
		_house = clan;
		_map.Visible = false;
		_map.HighlightedDoor = Clan.None;
		foreach (OverworldNpc p in _townPeople)
		{
			p.Visible = false;
		}
		ClearNearest();
		_interior = new HouseInterior();
		_interior.Setup(clan);
		AddChild(_interior);
		MoveChild(_interior, _world.GetIndex());
		foreach (NpcData npc in Npcs)
		{
			if (npc == null || npc.House != clan)
			{
				continue;
			}
			var person = new OverworldNpc();
			person.SetupNpc(npc);
			person.Position += HouseInterior.Origin;
			_world.AddChild(person);
			_hallPeople.Add(person);
		}
		_player.Position = at ?? HouseInterior.Origin + HouseInterior.EntryPoint;
		SetCameraLimits(new Rect2(HouseInterior.Origin, HouseInterior.RoomSize));
		RenderingServer.SetDefaultClearColor(HallClearColor);
	}

	/// <summary>Removes the hall and shows the town again, the player in front of the hall's door.</summary>
	private void ShowTown()
	{
		Clan left = _house;
		_house = Clan.None;
		ClearNearest();
		foreach (OverworldNpc p in _hallPeople)
		{
			p.QueueFree();
		}
		_hallPeople.Clear();
		_interior?.QueueFree();
		_interior = null;
		_map.Visible = true;
		foreach (OverworldNpc p in _townPeople)
		{
			p.Visible = true;
		}
		foreach (TownMap.House h in _map.Houses)
		{
			if (h.Clan == left)
			{
				_player.Position = TownMap.DoorOf(h) + new Vector2(0, 26);
			}
		}
		SetCameraLimits(new Rect2(Vector2.Zero, TownMap.MapSize));
		RenderingServer.SetDefaultClearColor(TownClearColor);
		UpdateHouseProgress();
	}

	private void ClearNearest()
	{
		if (_nearest != null)
		{
			_nearest.Highlighted = false;
			_nearest = null;
		}
	}

	/// <summary>The duelist of a hall that requires others (its clan leader), or null.</summary>
	private NpcData FindLeader(Clan clan)
	{
		foreach (NpcData npc in Npcs)
		{
			if (npc != null && npc.House == clan && npc.RequiresDefeated.Count > 0)
			{
				return npc;
			}
		}
		return null;
	}

	/// <summary>Updates the star signs above the hall doors (duelists of each hall beaten / total).</summary>
	private void UpdateHouseProgress()
	{
		foreach (TownMap.House h in _map.Houses)
		{
			int total = 0;
			int beaten = 0;
			foreach (NpcData npc in Npcs)
			{
				if (npc != null && npc.House == h.Clan)
				{
					total++;
					beaten += PlayerProfile.HasDefeated(npc.Id) ? 1 : 0;
				}
			}
			_map.SetHouseProgress(h.Clan, beaten, total);
		}
	}

	// ------------------------------------------------------------------ talking

	private void Talk(OverworldNpc person)
	{
		person.FaceToward(_player.GlobalPosition);
		if (person.Vendor != null)
		{
			VendorData v = person.Vendor;
			_ui.Dialogue.Open(v.Name, new Color(1f, 0.85f, 0.5f), v.Title, v.Greeting, new List<(string, System.Action)>
			{
				("Trade", () =>
				{
					EndTalk();
					_player.InputEnabled = false;
					_ui.Shop.OpenFor(v);
				}),
				("Leave", EndTalk),
			});
			return;
		}
		NpcData npc = person.Npc;
		if (!BattleSession.IsUnlocked(npc, out int done, out int needed))
		{
			string locked = string.IsNullOrEmpty(npc.LockedLine) ? "Come back when you are ready." : npc.LockedLine;
			string what = npc.House != Clan.None ? "Duelists of this hall defeated" : "Clan leaders defeated";
			_ui.Dialogue.Open(npc.Name, new Color(0.75f, 0.3f, 0.95f), npc.Title,
				$"{locked}\n\n[color=#6b4a2a]{what}: [b]{done} / {needed}[/b] · {BattleSession.DescribeReward(npc)}[/color]",
				new List<(string, System.Action)> { ("Leave", EndTalk) });
			return;
		}
		bool beaten = PlayerProfile.HasDefeated(npc.Id);
		string line = beaten && !string.IsNullOrEmpty(npc.RematchLine) ? npc.RematchLine : npc.Greeting;
		string deckName = npc.Deck?.Name ?? "?";
		string text = $"{line}\n\n[color=#6b4a2a]{ClanInfo.GetName(npc.Clan)} · plays [b]{deckName}[/b] · {DescribeStrength(npc)} · "
			+ $"{BattleSession.DescribeReward(npc)}[/color]";
		_ui.Dialogue.Open(npc.Name, ClanInfo.GetColor(npc.Clan).Darkened(0.1f), npc.Title, text, new List<(string, System.Action)>
		{
			(beaten ? "Rematch!" : "Battle!", () => StartBattle(npc)),
			("Leave", EndTalk),
		});
	}

	/// <summary>Rough deck strength for the dialogue (average card rarity, plus the duelist's bonus AP).</summary>
	private static string DescribeStrength(NpcData npc)
	{
		if (npc.Deck == null || npc.Deck.Cards.Count == 0)
		{
			return "?";
		}
		float rarity = 0f;
		foreach (CardData card in npc.Deck.Cards)
		{
			rarity += card != null ? (int)card.Rarity : 0;
		}
		rarity /= npc.Deck.Cards.Count;
		if (npc.BonusApPerTurn > 0 || rarity >= 1.2f)
		{
			return "[color=#a02020]Boss[/color]";
		}
		return rarity >= 0.8f ? "Hard" : rarity >= 0.35f ? "Medium" : "Easy";
	}

	private void EndTalk()
	{
		_ui.Dialogue.Close();
	}

	private void StartBattle(NpcData npc)
	{
		if (!PlayerProfile.DeckIsValid)
		{
			_ui.Dialogue.Open(npc.Name, ClanInfo.GetColor(npc.Clan), npc.Title,
				$"Come back with a proper deck! You need {PlayerProfile.DeckMin} to {PlayerProfile.DeckMax} cards - yours has {PlayerProfile.DeckCount}.",
				new List<(string, System.Action)>
				{
					("Deck Builder", () =>
					{
						EndTalk();
						OpenDeckBuilder();
					}),
					("Leave", EndTalk),
				});
			return;
		}
		if (npc.Deck == null || npc.Deck.Cards.Count == 0)
		{
			_ui.ShowToast($"{npc.Name} has no deck to play with.");
			return;
		}
		EndTalk();
		_transitioning = true;
		_player.InputEnabled = false;
		Sfx.Play(SfxId.TurnEnemy);
		BattleSession.Begin(npc, _player.GlobalPosition, _house);
		Tween fade = CreateTween();
		fade.TweenProperty(this, "modulate", new Color(0.1f, 0.1f, 0.1f), 0.45f);
		fade.TweenCallback(Callable.From(() => GetTree().ChangeSceneToFile(BattleSession.BattleScene)));
	}

	private void OpenDeckBuilder()
	{
		EndTalk();
		_player.InputEnabled = false;
		_ui.DeckBuilder.Open();
	}

	private void GreetAfterBattle()
	{
		NpcData npc = BattleSession.LastOpponent;
		string message = BattleSession.PendingMessage;
		BattleSession.LastOpponent = null;
		BattleSession.PendingMessage = "";
		if (npc == null || string.IsNullOrEmpty(message))
		{
			_ui.ShowToast("Welcome to Realmshatter! Duel the townsfolk, enter the clan halls - or visit the market.", 5f);
			return;
		}
		OverworldNpc person = ActivePeople.Find(p => p.Npc == npc);
		person?.FaceToward(_player.GlobalPosition);
		bool won = BattleSession.LastWon;
		string line = won ? npc.DefeatLine : npc.VictoryLine;
		string unlocked = won ? DescribeUnlock(npc) : "";
		_ui.Dialogue.Open(npc.Name, ClanInfo.GetColor(npc.Clan).Darkened(0.1f), npc.Title, $"{line}\n\n[b]{message}[/b]{unlocked}",
			new List<(string, System.Action)> { ("Continue", EndTalk) });
		Sfx.Play(won ? SfxId.Coin : SfxId.SpellFade);
	}

	/// <summary>Text about a duelist the win just unlocked (the hall's leader or the endboss), or "".</summary>
	private string DescribeUnlock(NpcData beaten)
	{
		foreach (NpcData npc in Npcs)
		{
			if (npc == null || !npc.RequiresDefeated.Contains(beaten.Id) || PlayerProfile.HasDefeated(npc.Id))
			{
				continue;
			}
			if (BattleSession.IsUnlocked(npc, out int done, out int needed))
			{
				return $"\n\n[color=#7a3a10]{npc.Name} ({npc.Title}) will now accept your challenge![/color]";
			}
			return $"\n\n[color=#6b4a2a]{done} / {needed} beaten on the way to {npc.Name}.[/color]";
		}
		return "";
	}
}
