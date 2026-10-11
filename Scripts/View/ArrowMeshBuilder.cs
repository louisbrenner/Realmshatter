using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Builds flat ribbon arrow meshes (for order_arrow.gdshader) from polylines, plus helpers to
/// round corners, trim ends and create arcs. Body UV.x = distance along the path, UV.y = across;
/// head triangle vertices carry UV2.x = 1.
/// </summary>
public static class ArrowMeshBuilder
{
	/// <summary>Replaces sharp polyline corners with quadratic Bezier fillets.</summary>
	public static List<Vector3> RoundCorners(IReadOnlyList<Vector3> points, float radius, int segments = 6)
	{
		var result = new List<Vector3>();
		if (points == null || points.Count == 0)
		{
			return result;
		}
		result.Add(points[0]);
		for (int i = 1; i < points.Count - 1; i++)
		{
			Vector3 prev = points[i - 1];
			Vector3 cur = points[i];
			Vector3 next = points[i + 1];
			Vector3 d0 = cur - prev;
			Vector3 d1 = next - cur;
			float l0 = d0.Length();
			float l1 = d1.Length();
			if (l0 < 0.0001f || l1 < 0.0001f || d0.Normalized().Dot(d1.Normalized()) > 0.999f)
			{
				result.Add(cur);
				continue;
			}
			float r = Mathf.Min(radius, Mathf.Min(l0, l1) * 0.5f);
			Vector3 a = cur - d0.Normalized() * r;
			Vector3 b = cur + d1.Normalized() * r;
			for (int s = 0; s <= segments; s++)
			{
				float t = (float)s / segments;
				float u = 1f - t;
				result.Add(a * (u * u) + cur * (2f * u * t) + b * (t * t));
			}
		}
		if (points.Count > 1)
		{
			result.Add(points[points.Count - 1]);
		}
		return result;
	}

	/// <summary>Quadratic arc from a to b rising to about 'height' with a sideways bulge (fraction of length).</summary>
	public static List<Vector3> Arc(Vector3 a, Vector3 b, float height, float sideBulge, int segments = 22)
	{
		var result = new List<Vector3>(segments + 1);
		Vector3 dir = b - a;
		var side = new Vector3(-dir.Z, 0f, dir.X);
		side = side.LengthSquared() > 0.0001f ? side.Normalized() : Vector3.Zero;
		Vector3 control = (a + b) * 0.5f + side * sideBulge * dir.Length() + Vector3.Up * height * 2f;
		for (int i = 0; i <= segments; i++)
		{
			float t = (float)i / segments;
			float u = 1f - t;
			result.Add(a * (u * u) + control * (2f * u * t) + b * (t * t));
		}
		return result;
	}

	/// <summary>
	/// Jagged lightning-like polyline from a to b: interior points are offset sideways (horizontally) by
	/// alternating, slightly randomized amounts up to 'amplitude'. Deterministic for a given seed.
	/// </summary>
	public static List<Vector3> Zigzag(Vector3 a, Vector3 b, float amplitude, int segments, float seed = 0f)
	{
		segments = Mathf.Max(2, segments);
		var result = new List<Vector3>(segments + 1);
		Vector3 dir = b - a;
		var side = new Vector3(-dir.Z, 0f, dir.X);
		side = side.LengthSquared() > 0.0001f ? side.Normalized() : Vector3.Right;
		for (int i = 0; i <= segments; i++)
		{
			float t = (float)i / segments;
			Vector3 p = a.Lerp(b, t);
			if (i > 0 && i < segments)
			{
				float r = Mathf.Abs(Mathf.Sin(seed * 12.9898f + i * 78.233f) * 43758.547f) % 1f;
				float sign = (i % 2 == 0) ? 1f : -1f;
				p += side * sign * amplitude * (0.55f + 0.45f * r);
			}
			result.Add(p);
		}
		return result;
	}

	/// <summary>Total length of a polyline.</summary>
	public static float Length(IReadOnlyList<Vector3> points)
	{
		float len = 0f;
		for (int i = 1; i < points.Count; i++)
		{
			len += points[i].DistanceTo(points[i - 1]);
		}
		return len;
	}

	/// <summary>Cuts the given distances off the start and the end of a polyline.</summary>
	public static List<Vector3> Trim(IReadOnlyList<Vector3> points, float startTrim, float endTrim)
	{
		var result = new List<Vector3>();
		if (points == null || points.Count < 2)
		{
			if (points != null)
			{
				result.AddRange(points);
			}
			return result;
		}
		float total = Length(points);
		float from = Mathf.Max(0f, startTrim);
		float to = Mathf.Max(from + 0.01f, total - Mathf.Max(0f, endTrim));
		if (to > total)
		{
			to = total;
		}
		float acc = 0f;
		result.Add(PointAt(points, from));
		for (int i = 1; i < points.Count; i++)
		{
			acc += points[i].DistanceTo(points[i - 1]);
			if (acc > from && acc < to)
			{
				result.Add(points[i]);
			}
		}
		result.Add(PointAt(points, to));
		return result;
	}

	/// <summary>Point at a distance along a polyline (clamped).</summary>
	public static Vector3 PointAt(IReadOnlyList<Vector3> points, float distance)
	{
		if (points.Count == 0)
		{
			return Vector3.Zero;
		}
		float acc = 0f;
		for (int i = 1; i < points.Count; i++)
		{
			float seg = points[i].DistanceTo(points[i - 1]);
			if (acc + seg >= distance && seg > 0f)
			{
				return points[i - 1].Lerp(points[i], (distance - acc) / seg);
			}
			acc += seg;
		}
		return points[points.Count - 1];
	}

	/// <summary>
	/// Builds a flat (horizontal) ribbon with an arrow head at the end of the polyline.
	/// Returns null if the polyline is too short.
	/// </summary>
	public static ArrayMesh BuildArrow(IReadOnlyList<Vector3> points, float width, float headLength, float headWidth)
	{
		if (points == null || points.Count < 2)
		{
			return null;
		}
		float total = Length(points);
		if (total < 0.08f)
		{
			return null;
		}
		float headLen = Mathf.Min(headLength, total * 0.6f);
		List<Vector3> body = Trim(points, 0f, headLen);
		Vector3 tip = points[points.Count - 1];

		var verts = new List<Vector3>();
		var uvs = new List<Vector2>();
		var uv2s = new List<Vector2>();
		var indices = new List<int>();

		float dist = 0f;
		Vector3 lastSide = Vector3.Right;
		for (int i = 0; i < body.Count; i++)
		{
			if (i > 0)
			{
				dist += body[i].DistanceTo(body[i - 1]);
			}
			Vector3 tangent = i == 0 ? body[1] - body[0]
				: i == body.Count - 1 ? body[i] - body[i - 1]
				: body[i + 1] - body[i - 1];
			tangent.Y = 0f;
			Vector3 side = tangent.LengthSquared() > 0.000001f ? new Vector3(-tangent.Z, 0f, tangent.X).Normalized() : lastSide;
			lastSide = side;
			verts.Add(body[i] - side * width * 0.5f);
			verts.Add(body[i] + side * width * 0.5f);
			uvs.Add(new Vector2(dist, 0f));
			uvs.Add(new Vector2(dist, 1f));
			uv2s.Add(Vector2.Zero);
			uv2s.Add(Vector2.Zero);
			if (i > 0)
			{
				int a = (i - 1) * 2;
				indices.Add(a);
				indices.Add(a + 2);
				indices.Add(a + 1);
				indices.Add(a + 1);
				indices.Add(a + 2);
				indices.Add(a + 3);
			}
		}

		Vector3 basePoint = body[body.Count - 1];
		Vector3 headDir = tip - basePoint;
		headDir.Y = 0f;
		Vector3 headSide = headDir.LengthSquared() > 0.000001f ? new Vector3(-headDir.Z, 0f, headDir.X).Normalized() : lastSide;
		int h = verts.Count;
		verts.Add(basePoint - headSide * headWidth * 0.5f);
		verts.Add(basePoint + headSide * headWidth * 0.5f);
		verts.Add(tip);
		uvs.Add(new Vector2(0f, 0f));
		uvs.Add(new Vector2(1f, 0f));
		uvs.Add(new Vector2(0.5f, 1f));
		uv2s.Add(new Vector2(1f, 0f));
		uv2s.Add(new Vector2(1f, 0f));
		uv2s.Add(new Vector2(1f, 0f));
		indices.Add(h);
		indices.Add(h + 1);
		indices.Add(h + 2);

		var normals = new Vector3[verts.Count];
		for (int i = 0; i < normals.Length; i++)
		{
			normals[i] = Vector3.Up;
		}

		var arrays = new Godot.Collections.Array();
		arrays.Resize((int)Mesh.ArrayType.Max);
		arrays[(int)Mesh.ArrayType.Vertex] = verts.ToArray();
		arrays[(int)Mesh.ArrayType.Normal] = normals;
		arrays[(int)Mesh.ArrayType.TexUV] = uvs.ToArray();
		arrays[(int)Mesh.ArrayType.TexUV2] = uv2s.ToArray();
		arrays[(int)Mesh.ArrayType.Index] = indices.ToArray();
		var mesh = new ArrayMesh();
		mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
		return mesh;
	}
}
