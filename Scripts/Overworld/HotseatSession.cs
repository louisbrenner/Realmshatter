using Godot;

namespace Realmshatter;

/// <summary>
/// Hand-over data for a local hotseat match (two humans on one device), started from the overworld.
/// Independent of BattleSession: no NPC, no rewards, the profile is never touched.
/// </summary>
public static class HotseatSession
{
	/// <summary>True while a hotseat match is pending / running.</summary>
	public static bool IsActive { get; private set; }

	/// <summary>Starts a hotseat match (call ChangeSceneToFile(BattleSession.BattleScene) afterwards).</summary>
	public static void Begin(Vector2 playerPosition, Clan house = Clan.None)
	{
		IsActive = true;
		BattleSession.ReturnPosition = playerPosition;
		BattleSession.ReturnHouse = house;
	}

	/// <summary>Ends the match; the overworld shows 'message' as a toast on return.</summary>
	public static void Complete(string message)
	{
		IsActive = false;
		BattleSession.PendingMessage = message ?? "";
	}
}
