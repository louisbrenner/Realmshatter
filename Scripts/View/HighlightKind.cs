namespace ProjectClaude;

/// <summary>Kind of a tile highlight drawn by BoardView. Later values are drawn on top.</summary>
public enum HighlightKind
{
	Move,
	Attack,
	Deploy,
	Spell,
	Selected,
	Hover,
}
