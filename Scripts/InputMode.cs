namespace Realmshatter;

/// <summary>State of the human player's input state machine in GameManager.</summary>
public enum InputMode
{
	/// <summary>Nothing selected; waiting for a card or piece selection.</summary>
	Idle,
	/// <summary>A hand card is selected; waiting for a deploy tile or spell target.</summary>
	CardSelected,
	/// <summary>An own piece is selected; waiting for its move destination (or its own tile = stay).</summary>
	ChoosingMove,
	/// <summary>The move step is done; waiting for the attack tile (or any other tile = move only).</summary>
	ChoosingAttack,
	/// <summary>A Builder is selected and the player picks the tile for its building.</summary>
	ChoosingBuild,
	/// <summary>A Trapper is selected and the player picks the tile for its trap.</summary>
	ChoosingTrap,
	/// <summary>Animations or the AI turn are running; human input is ignored.</summary>
	Busy,
}
