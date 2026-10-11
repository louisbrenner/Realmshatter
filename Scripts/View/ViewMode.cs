namespace ProjectClaude;

/// <summary>Camera presentation mode of the board.</summary>
public enum ViewMode
{
	/// <summary>Orthographic, straight top-down.</summary>
	TwoD,
	/// <summary>Orthographic, angled (isometric-like).</summary>
	TwoPointFiveD,
	/// <summary>Perspective, angled from player 0's side.</summary>
	ThreeD,
}
