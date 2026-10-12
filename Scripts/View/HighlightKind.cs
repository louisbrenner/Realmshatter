namespace Realmshatter;

/// <summary>Kind of a tile highlight drawn by BoardView. Later values are drawn on top.</summary>
public enum HighlightKind
{
	Move,
	Attack,
	Deploy,
	Spell,
	Selected,
	Hover,
	/// <summary>Reach of a building or the spell cast range (drawn faintly beneath the other kinds).</summary>
	Range,
}
