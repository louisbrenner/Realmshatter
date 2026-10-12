namespace Realmshatter;

/// <summary>Phase of the current turn.</summary>
public enum GamePhase
{
	/// <summary>Game created but StartGame not called yet.</summary>
	NotStarted,
	/// <summary>Current player must choose one card of the draft offer.</summary>
	Draft,
	/// <summary>Current player may play cards and command pieces.</summary>
	Main,
	/// <summary>The turn is being handed over (transient, inside EndTurn).</summary>
	Resolving,
	/// <summary>A player reached the points target; Winner is set.</summary>
	GameOver,
}
