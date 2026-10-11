using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Jagged, camera-facing lightning ribbon between two world points that re-jitters a few times
/// per frame-second and fades out, then frees itself. Create via Vfx.Lightning.
/// </summary>
public partial class LightningArc : MeshInstance3D
{
	private const float JitterInterval = 0.045f;

	private readonly RandomNumberGenerator _rng = new RandomNumberGenerator();
	private Vector3 _from;
	private Vector3 _to;
	private Color _color = new Color(0.6f, 0.8f, 1f);
	private float _duration = 0.35f;
	private float _time;
	private float _nextJitter;
	private ImmediateMesh _mesh;
	private ShaderMaterial _material;

	/// <summary>Sets endpoints (world space), color and lifetime. Call before adding to the tree.</summary>
	public void Setup(Vector3 fromWorld, Vector3 toWorld, Color color, float duration)
	{
		_from = fromWorld;
		_to = toWorld;
		_color = color;
		_duration = Mathf.Max(0.05f, duration);
	}

	public override void _Ready()
	{
		_mesh = new ImmediateMesh();
		Mesh = _mesh;
		_material = VfxAssets.CreateMaterial("vfx_ribbon", 6);
		_material.SetShaderParameter("color", _color);
		MaterialOverride = _material;
		CastShadow = ShadowCastingSetting.Off;
		Rebuild();
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		if (_time >= _duration)
		{
			QueueFree();
			return;
		}
		float k = 1f - _time / _duration;
		_material.SetShaderParameter("opacity", Mathf.Clamp(k * 1.4f, 0f, 1f));
		_nextJitter -= (float)delta;
		if (_nextJitter <= 0f)
		{
			Rebuild();
			_nextJitter = JitterInterval;
		}
	}

	private void Rebuild()
	{
		Camera3D camera = GetViewport()?.GetCamera3D();
		Vector3 viewDir = camera != null ? camera.GlobalTransform.Basis.Z.Normalized() : Vector3.Up;
		_mesh.ClearSurfaces();
		_mesh.SurfaceBegin(Mesh.PrimitiveType.Triangles);
		AddBolt(BuildPoints(0.2f), viewDir, 0.13f);
		AddBolt(BuildPoints(0.32f), viewDir, 0.06f);
		_mesh.SurfaceEnd();
	}

	private List<Vector3> BuildPoints(float jitter)
	{
		const int segments = 14;
		var points = new List<Vector3>(segments + 1);
		Vector3 dir = _to - _from;
		float len = dir.Length();
		Vector3 side = dir.Cross(Vector3.Up);
		side = side.LengthSquared() > 0.0001f ? side.Normalized() : Vector3.Right;
		for (int i = 0; i <= segments; i++)
		{
			float t = (float)i / segments;
			Vector3 p = _from.Lerp(_to, t) + Vector3.Up * Mathf.Sin(t * Mathf.Pi) * 0.12f * len;
			if (i > 0 && i < segments)
			{
				p += side * _rng.RandfRange(-jitter, jitter) + Vector3.Up * _rng.RandfRange(-jitter, jitter) * 0.6f;
			}
			points.Add(ToLocal(p));
		}
		return points;
	}

	private void AddBolt(List<Vector3> points, Vector3 viewDirWorld, float width)
	{
		Vector3 viewDir = (GlobalTransform.Basis.Inverse() * viewDirWorld).Normalized();
		for (int i = 0; i < points.Count - 1; i++)
		{
			Vector3 a = points[i];
			Vector3 b = points[i + 1];
			Vector3 seg = b - a;
			Vector3 w = seg.Cross(viewDir);
			w = w.LengthSquared() > 0.000001f ? w.Normalized() * width * 0.5f : Vector3.Right * width * 0.5f;
			float ta = (float)i / (points.Count - 1);
			float tb = (float)(i + 1) / (points.Count - 1);
			AddVertex(a - w, new Vector2(ta, 0f));
			AddVertex(a + w, new Vector2(ta, 1f));
			AddVertex(b + w, new Vector2(tb, 1f));
			AddVertex(a - w, new Vector2(ta, 0f));
			AddVertex(b + w, new Vector2(tb, 1f));
			AddVertex(b - w, new Vector2(tb, 0f));
		}
	}

	private void AddVertex(Vector3 v, Vector2 uv)
	{
		_mesh.SurfaceSetUV(uv);
		_mesh.SurfaceAddVertex(v);
	}
}
