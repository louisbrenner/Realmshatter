using System.Collections.Generic;

namespace Realmshatter;

/// <summary>Per-player resources and cards.</summary>
public sealed class PlayerState
{
	public int Index { get; }
	public int VictoryPoints { get; set; }
	public int ActionPoints { get; set; }
	/// <summary>Victory points converted into action points during the current turn (reset at turn start).</summary>
	public int VpConvertedThisTurn { get; internal set; }
	/// <summary>Extra AP at the start of every one of this player's turns (e.g. the endboss).</summary>
	public int BonusApPerTurn { get; set; }
	/// <summary>AP added at the start of this player's next turn (Tribute deathrattles, Plunder on the enemy's turn).</summary>
	public int PendingAp { get; set; }
	/// <summary>Number of turns this player has started (1 during its first turn).</summary>
	public int TurnsStarted { get; internal set; }
	public List<CardData> Hand { get; } = new List<CardData>();
	/// <summary>Remaining draw pile. Draft offers are drawn from here; unpicked cards and destroyed Undying pieces return to it.</summary>
	public List<CardData> Deck { get; } = new List<CardData>();
	/// <summary>Cards of destroyed pieces (lost for the rest of the game).</summary>
	public List<CardData> Graveyard { get; } = new List<CardData>();
	/// <summary>Current draft offer (up to DraftOfferSize cards); empty when no draft is pending.</summary>
	public List<CardData> DraftOffer { get; } = new List<CardData>();

	public PlayerState(int index, IEnumerable<CardData> deck)
	{
		Index = index;
		if (deck != null)
		{
			Deck.AddRange(deck);
		}
	}

	/// <summary>Copy for state clones (card lists are copied, cards are shared).</summary>
	internal PlayerState(PlayerState other)
	{
		Index = other.Index;
		VictoryPoints = other.VictoryPoints;
		ActionPoints = other.ActionPoints;
		VpConvertedThisTurn = other.VpConvertedThisTurn;
		TurnsStarted = other.TurnsStarted;
		PendingAp = other.PendingAp;
		BonusApPerTurn = other.BonusApPerTurn;
		Hand.AddRange(other.Hand);
		Deck.AddRange(other.Deck);
		DraftOffer.AddRange(other.DraftOffer);
		Graveyard.AddRange(other.Graveyard);
	}
}
