using Godot;

namespace ProjectClaude;

/// <summary>
/// Straight, camera-facing glowing beam between two world points (e.g. a Pierce lance) that shoots out
/// from the start, flares and thins out, then frees itself. Create via RuleVfx.Beam.
/// </summary>
public partial class BeamEffect : MeshInstance3D
{
	private Vector3 _from;
	private Vector3 _to;
	private Color _color = new Color(1f, 0.8f, 0.5f);
	private float _duration = 0.35f;
	private float _width = 0.22f;
	private float _time;
	private ImmediateMesh _mesh;
	private ShaderMaterial _material;

	/// <summary>Sets endpoints (world space), color, lifetime and width. Call before adding to the tree.</summary>
	public void Setup(Vector3 fromWorld, Vector3 toWorld, Color color, float duration, float width = 0.22f)
	{
		_from = fromWorld;
		_to = toWorld;
		_color = color;
		_duration = Mathf.Max(0.05f, duration);
		_width = width;
	}

	public override void _Ready()
	{
		_mesh = new ImmediateMesh();
		Mesh = _mesh;
		_material = VfxAssets.CreateMaterial("vfx_ribbon", 6);
		_material.SetShaderParameter("color", _color);
		_material.SetShaderParameter("energy", 5f);
		MaterialOverride = _material;
		CastShadow = ShadowCastingSetting.Off;
		Rebuild(0f);
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		float t = _time / _duration;
		if (t >= 1f)
		{
			QueueFree();
			return;
		}
		Rebuild(t);
	}

	private void Rebuild(float t)
	{
		float extend = Mathf.Clamp(t / 0.25f, 0f, 1f);
		float fade = t < 0.25f ? 1f : 1f - (t - 0.25f) / 0.75f;
		float width = _width * (t < 0.25f ? 0.6f + 0.6f * extend : 1.2f * fade + 0.05f);
		_material.SetShaderParameter("opacity", Mathf.Clamp(fade * 1.3f, 0f, 1f));

		Camera3D camera = GetViewport()?.GetCamera3D();
		Vector3 viewDirWorld = camera != null ? camera.GlobalTransform.Basis.Z.Normalized() : Vector3.Up;
		Vector3 viewDir = (GlobalTransform.Basis.Inverse() * viewDirWorld).Normalized();
		Vector3 a = ToLocal(_from);
		Vector3 b = ToLocal(_from.Lerp(_to, extend));
		Vector3 seg = b - a;
		Vector3 w = seg.Cross(viewDir);
		w = w.LengthSquared() > 0.000001f ? w.Normalized() * width * 0.5f : Vector3.Right * width * 0.5f;

		_mesh.ClearSurfaces();
		_mesh.SurfaceBegin(Mesh.PrimitiveType.Triangles);
		AddVertex(a - w, new Vector2(0f, 0f));
		AddVertex(a + w, new Vector2(0f, 1f));
		AddVertex(b + w, new Vector2(1f, 1f));
		AddVertex(a - w, new Vector2(0f, 0f));
		AddVertex(b + w, new Vector2(1f, 1f));
		AddVertex(b - w, new Vector2(1f, 0f));
		_mesh.SurfaceEnd();
	}

	private void AddVertex(Vector3 v, Vector2 uv)
	{
		_mesh.SurfaceSetUV(uv);
		_mesh.SurfaceAddVertex(v);
	}
}
