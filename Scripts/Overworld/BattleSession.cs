using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Hand-over between the overworld and the battle scene: which NPC is challenged, where the player stood, and the
/// result message shown back in town. Rewards: first win = NPC gold + reward cards, rematch win = half the gold,
/// loss = a small consolation.
/// </summary>
public static class BattleSession
{
	public const string BattleScene = "res://Scenes/Main.tscn";
	public const string OverworldScene = "res://Scenes/Overworld.tscn";
	/// <summary>Share of an NPC's gold reward the player loses on a defeat (at least MinLossGold).</summary>
	public const int LossDivisor = 4;
	public const int MinLossGold = 5;

	/// <summary>The NPC being fought, or null outside a town battle.</summary>
	public static NpcData Opponent { get; private set; }

	/// <summary>True while a town battle is pending / running.</summary>
	public static bool IsActive => Opponent != null;

	/// <summary>Where the player stood before the battle (restored on return).</summary>
	public static Vector2? ReturnPosition { get; set; }

	/// <summary>Clan hall the player was in before the battle (None = the town).</summary>
	public static Clan ReturnHouse { get; set; } = Clan.None;

	/// <summary>Message for the overworld after a battle (consumed once shown).</summary>
	public static string PendingMessage { get; set; } = "";

	/// <summary>The NPC of the last finished battle (for its after-battle line), or null.</summary>
	public static NpcData LastOpponent { get; set; }

	/// <summary>True if the player won the last finished battle.</summary>
	public static bool LastWon { get; private set; }

	/// <summary>Starts a battle against the NPC (call ChangeSceneToFile(BattleScene) afterwards).</summary>
	public static void Begin(NpcData npc, Vector2 playerPosition, Clan house = Clan.None)
	{
		Opponent = npc;
		ReturnPosition = playerPosition;
		ReturnHouse = house;
	}

	/// <summary>The player's profile deck wrapped in a DeckData for the battle.</summary>
	public static DeckData BuildPlayerDeck()
	{
		var deck = new DeckData { Name = "Your Deck" };
		foreach (CardData card in PlayerProfile.GetDeck())
		{
			deck.Cards.Add(card);
		}
		return deck;
	}

	/// <summary>Text listing what a win against the NPC would give.</summary>
	public static string DescribeReward(NpcData npc)
	{
		if (npc == null)
		{
			return "";
		}
		string stake = $" Defeat costs {LossGold(npc)} gold.";
		if (PlayerProfile.HasDefeated(npc.Id))
		{
			return $"Rematch reward: {npc.RewardGold / 2} gold.{stake}";
		}
		var names = new List<string>(CountedNames(npc.RewardCards));
		if (npc.RewardOneOf.Count > 0)
		{
			names.Add("one Legendary card you do not own yet");
		}
		string reward = names.Count > 0 ? $"Reward: {npc.RewardGold} gold + {string.Join(", ", names)}." : $"Reward: {npc.RewardGold} gold.";
		return reward + stake;
	}

	/// <summary>Gold the player loses when this NPC wins: a quarter of its reward, at least MinLossGold.</summary>
	public static int LossGold(NpcData npc) => npc == null ? 0 : System.Math.Max(MinLossGold, npc.RewardGold / LossDivisor);

	/// <summary>"Ember Imp x2, Fireball" - card names with their copy counts, in list order.</summary>
	private static List<string> CountedNames(IEnumerable<CardData> cards)
	{
		var order = new List<string>();
		var counts = new Dictionary<string, int>();
		foreach (CardData card in cards)
		{
			if (card == null)
			{
				continue;
			}
			if (!counts.ContainsKey(card.Name))
			{
				order.Add(card.Name);
				counts[card.Name] = 0;
			}
			counts[card.Name]++;
		}
		return order.ConvertAll(n => counts[n] > 1 ? $"{n} x{counts[n]}" : n);
	}

	/// <summary>A random card of the NPC's RewardOneOf list that the player does not own yet (any, if all are owned).</summary>
	private static CardData PickOneOf(NpcData npc)
	{
		var unowned = new List<CardData>();
		var all = new List<CardData>();
		foreach (CardData card in npc.RewardOneOf)
		{
			if (card == null)
			{
				continue;
			}
			all.Add(card);
			if (PlayerProfile.OwnedCount(card) == 0)
			{
				unowned.Add(card);
			}
		}
		List<CardData> pool = unowned.Count > 0 ? unowned : all;
		return pool.Count > 0 ? pool[(int)(GD.Randi() % (uint)pool.Count)] : null;
	}

	/// <summary>
	/// True if the player has beaten every duelist the NPC requires (a clan leader waits for the three duelists of
	/// its hall, the endboss for the clan leaders).
	/// </summary>
	public static bool IsUnlocked(NpcData npc, out int beaten, out int needed)
	{
		beaten = 0;
		needed = npc?.RequiresDefeated.Count ?? 0;
		if (npc == null)
		{
			return false;
		}
		foreach (string id in npc.RequiresDefeated)
		{
			beaten += PlayerProfile.HasDefeated(id) ? 1 : 0;
		}
		return beaten >= needed;
	}

	/// <summary>Applies the result to the profile, clears the session and returns the summary text.</summary>
	public static string Complete(bool won)
	{
		NpcData npc = Opponent;
		Opponent = null;
		if (npc == null)
		{
			return "";
		}
		LastOpponent = npc;
		LastWon = won;
		string text;
		if (won)
		{
			bool first = !PlayerProfile.HasDefeated(npc.Id);
			int gold = first ? npc.RewardGold : npc.RewardGold / 2;
			PlayerProfile.AddGold(gold);
			var gained = new List<CardData>();
			string unlock = "";
			if (first)
			{
				// RewardCards may list a card several times: one copy per entry.
				foreach (CardData card in npc.RewardCards)
				{
					if (card != null)
					{
						PlayerProfile.AddCard(card);
						gained.Add(card);
					}
				}
				CardData pick = PickOneOf(npc);
				if (pick != null)
				{
					PlayerProfile.AddCard(pick);
					gained.Add(pick);
				}
				PlayerProfile.MarkDefeated(npc.Id);
				if (npc.Clan != Clan.None && ShopUnlocks.IdPrefix(npc.Clan) != "" && npc.Id.StartsWith(ShopUnlocks.IdPrefix(npc.Clan)))
				{
					unlock = ShopUnlocks.LeaderDefeated(npc.Clan)
						? $" Every {ClanInfo.GetName(npc.Clan)} card is now sold in the shops!"
						: $" New {ClanInfo.GetName(npc.Clan)} cards are now sold in the shops.";
				}
			}
			text = $"You beat {npc.Name}! +{gold} gold" + (gained.Count > 0 ? $", new cards: {string.Join(", ", CountedNames(gained))}." : ".") + unlock;
		}
		else
		{
			int loss = System.Math.Min(LossGold(npc), PlayerProfile.Gold);
			PlayerProfile.AddGold(-loss);
			text = loss > 0 ? $"{npc.Name} won and takes {loss} gold from you." : $"{npc.Name} won - luckily your purse was already empty.";
		}
		PendingMessage = text;
		return text;
	}
}
