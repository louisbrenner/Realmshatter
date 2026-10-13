using System;
using System.Collections.Generic;
using System.Text.Json;
using Godot;

namespace Realmshatter;

/// <summary>
/// The player's persistent progress: gold, card collection (card resource path -> copies), the current deck
/// (list of card paths) and the NPCs already defeated. Stored as JSON in user://. Static so it survives scene
/// changes without an autoload. A new profile starts with the Starter Deck and StartingGold.
/// </summary>
public static class PlayerProfile
{
	public const string SavePath = "user://realmshatter_profile.json";
	public const string StarterDeckPath = "res://Resources/Decks/StarterDeck.tres";
	public const int StartingGold = 120;
	public const int DeckMin = 25;
	public const int DeckMax = 40;
	public const int MaxCopies = 3;
	/// <summary>Save format / balance version; older saves are discarded (e.g. after a card rebalance).</summary>
	public const int SaveVersion = 4;

	private sealed class SaveDto
	{
		public int Version { get; set; }
		public int Gold { get; set; }
		public Dictionary<string, int> Collection { get; set; } = new Dictionary<string, int>();
		public List<string> Deck { get; set; } = new List<string>();
		public List<string> Defeated { get; set; } = new List<string>();
	}

	private static readonly Dictionary<string, int> Owned = new Dictionary<string, int>();
	private static readonly List<string> DeckPaths = new List<string>();
	private static readonly HashSet<string> DefeatedIds = new HashSet<string>();
	private static readonly Dictionary<string, CardData> Cache = new Dictionary<string, CardData>();
	private static bool _loaded;

	/// <summary>Raised whenever gold, collection or deck change.</summary>
	public static event Action Changed;

	/// <summary>Current gold.</summary>
	public static int Gold { get; private set; }

	/// <summary>Card path -> owned copies.</summary>
	public static IReadOnlyDictionary<string, int> Collection
	{
		get
		{
			EnsureLoaded();
			return Owned;
		}
	}

	/// <summary>Number of cards in the deck.</summary>
	public static int DeckCount
	{
		get
		{
			EnsureLoaded();
			return DeckPaths.Count;
		}
	}

	/// <summary>True if the deck size is within DeckMin..DeckMax.</summary>
	public static bool DeckIsValid => DeckCount >= DeckMin && DeckCount <= DeckMax;

	/// <summary>Loads the save game once (or creates the starter profile).</summary>
	public static void EnsureLoaded()
	{
		if (_loaded)
		{
			return;
		}
		_loaded = true;
		if (!Load())
		{
			ResetToStarter();
		}
	}

	/// <summary>Discards all progress and starts over with the Starter Deck.</summary>
	public static void ResetToStarter()
	{
		_loaded = true;
		Owned.Clear();
		DeckPaths.Clear();
		DefeatedIds.Clear();
		Gold = StartingGold;
		DeckData starter = GD.Load<DeckData>(StarterDeckPath);
		if (starter != null)
		{
			foreach (CardData card in starter.Cards)
			{
				if (card != null && !string.IsNullOrEmpty(card.ResourcePath))
				{
					Owned.TryGetValue(card.ResourcePath, out int n);
					Owned[card.ResourcePath] = n + 1;
					DeckPaths.Add(card.ResourcePath);
				}
			}
		}
		Save();
	}

	/// <summary>Loads a card resource by path (cached).</summary>
	public static CardData GetCard(string path)
	{
		if (string.IsNullOrEmpty(path))
		{
			return null;
		}
		if (!Cache.TryGetValue(path, out CardData card))
		{
			card = ResourceLoader.Exists(path) ? GD.Load<CardData>(path) : null;
			Cache[path] = card;
		}
		return card;
	}

	/// <summary>Owned copies of a card.</summary>
	public static int OwnedCount(CardData card)
	{
		EnsureLoaded();
		return card != null && Owned.TryGetValue(card.ResourcePath, out int n) ? n : 0;
	}

	/// <summary>Copies of a card in the deck.</summary>
	public static int InDeckCount(CardData card)
	{
		EnsureLoaded();
		if (card == null)
		{
			return 0;
		}
		int n = 0;
		foreach (string p in DeckPaths)
		{
			n += p == card.ResourcePath ? 1 : 0;
		}
		return n;
	}

	/// <summary>The deck as card resources (missing resources are skipped).</summary>
	public static List<CardData> GetDeck()
	{
		EnsureLoaded();
		var list = new List<CardData>();
		foreach (string p in DeckPaths)
		{
			CardData card = GetCard(p);
			if (card != null)
			{
				list.Add(card);
			}
		}
		return list;
	}

	/// <summary>All owned cards (one entry per card type), sorted by AP cost then name.</summary>
	public static List<CardData> GetOwnedCards()
	{
		EnsureLoaded();
		var list = new List<CardData>();
		foreach (string p in Owned.Keys)
		{
			CardData card = GetCard(p);
			if (card != null && Owned[p] > 0)
			{
				list.Add(card);
			}
		}
		list.Sort((a, b) =>
		{
			int ca = a.ApCost > 0 ? a.ApCost : 1;
			int cb = b.ApCost > 0 ? b.ApCost : 1;
			return ca != cb ? ca.CompareTo(cb) : string.Compare(a.Name, b.Name, StringComparison.Ordinal);
		});
		return list;
	}

	/// <summary>Adds a copy to the deck if one is owned and not yet used, the copy limit and DeckMax allow it.</summary>
	public static bool TryAddToDeck(CardData card, out string error)
	{
		EnsureLoaded();
		error = "";
		int inDeck = InDeckCount(card);
		if (card == null || inDeck >= OwnedCount(card))
		{
			error = "You have no more copies of this card.";
			return false;
		}
		if (inDeck >= MaxCopies)
		{
			error = $"At most {MaxCopies} copies of a card per deck.";
			return false;
		}
		if (card.Rarity == CardRarity.Legendary && inDeck >= 1)
		{
			error = "Only one copy of a Legendary card per deck.";
			return false;
		}
		if (DeckPaths.Count >= DeckMax)
		{
			error = $"A deck holds at most {DeckMax} cards.";
			return false;
		}
		DeckPaths.Add(card.ResourcePath);
		SaveAndNotify();
		return true;
	}

	/// <summary>Removes one copy from the deck.</summary>
	public static bool RemoveFromDeck(CardData card)
	{
		EnsureLoaded();
		if (card == null || !DeckPaths.Remove(card.ResourcePath))
		{
			return false;
		}
		SaveAndNotify();
		return true;
	}

	/// <summary>Adds owned copies (purchases, rewards).</summary>
	public static void AddCard(CardData card, int copies = 1)
	{
		EnsureLoaded();
		if (card == null || string.IsNullOrEmpty(card.ResourcePath) || copies <= 0)
		{
			return;
		}
		Owned.TryGetValue(card.ResourcePath, out int n);
		Owned[card.ResourcePath] = n + copies;
		SaveAndNotify();
	}

	/// <summary>Buys a card for its BuyPrice. False if gold is short.</summary>
	public static bool TryBuy(CardData card, out string error)
	{
		EnsureLoaded();
		int price = CardEconomy.BuyPrice(card);
		if (Gold < price)
		{
			error = $"Not enough gold ({price} needed).";
			return false;
		}
		error = "";
		Gold -= price;
		AddCard(card);
		return true;
	}

	/// <summary>Sells one copy for its SellPrice; a copy used in the deck is removed from it.</summary>
	public static bool TrySell(CardData card, out string error)
	{
		EnsureLoaded();
		int owned = OwnedCount(card);
		if (owned <= 0)
		{
			error = "You do not own this card.";
			return false;
		}
		error = "";
		Owned[card.ResourcePath] = owned - 1;
		if (owned - 1 <= 0)
		{
			Owned.Remove(card.ResourcePath);
		}
		if (InDeckCount(card) > owned - 1)
		{
			DeckPaths.Remove(card.ResourcePath);
		}
		Gold += CardEconomy.SellPrice(card);
		SaveAndNotify();
		return true;
	}

	/// <summary>Adds (or with a negative amount removes) gold.</summary>
	public static void AddGold(int amount)
	{
		EnsureLoaded();
		Gold = Math.Max(0, Gold + amount);
		SaveAndNotify();
	}

	/// <summary>True if the NPC was beaten at least once.</summary>
	public static bool HasDefeated(string npcId)
	{
		EnsureLoaded();
		return !string.IsNullOrEmpty(npcId) && DefeatedIds.Contains(npcId);
	}

	/// <summary>Marks an NPC as beaten.</summary>
	public static void MarkDefeated(string npcId)
	{
		EnsureLoaded();
		if (!string.IsNullOrEmpty(npcId) && DefeatedIds.Add(npcId))
		{
			SaveAndNotify();
		}
	}

	/// <summary>Number of NPCs beaten.</summary>
	public static int DefeatedCount
	{
		get
		{
			EnsureLoaded();
			return DefeatedIds.Count;
		}
	}

	/// <summary>Writes the profile to user://.</summary>
	public static void Save()
	{
		var dto = new SaveDto
		{
			Version = SaveVersion,
			Gold = Gold,
			Collection = new Dictionary<string, int>(Owned),
			Deck = new List<string>(DeckPaths),
			Defeated = new List<string>(DefeatedIds),
		};
		using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Write);
		file?.StoreString(JsonSerializer.Serialize(dto, new JsonSerializerOptions { WriteIndented = true }));
	}

	private static bool Load()
	{
		if (!FileAccess.FileExists(SavePath))
		{
			return false;
		}
		try
		{
			using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Read);
			SaveDto dto = file != null ? JsonSerializer.Deserialize<SaveDto>(file.GetAsText()) : null;
			if (dto == null || dto.Version != SaveVersion)
			{
				return false;
			}
			Gold = Math.Max(0, dto.Gold);
			Owned.Clear();
			foreach (KeyValuePair<string, int> kv in dto.Collection)
			{
				if (kv.Value > 0 && GetCard(kv.Key) != null)
				{
					Owned[kv.Key] = kv.Value;
				}
			}
			DeckPaths.Clear();
			foreach (string p in dto.Deck)
			{
				if (GetCard(p) != null)
				{
					DeckPaths.Add(p);
				}
			}
			DefeatedIds.Clear();
			DefeatedIds.UnionWith(dto.Defeated);
			return Owned.Count > 0;
		}
		catch (Exception e)
		{
			GD.PushWarning($"PlayerProfile: could not read the save game ({e.Message}); starting fresh.");
			return false;
		}
	}

	private static void SaveAndNotify()
	{
		Save();
		Changed?.Invoke();
	}
}
