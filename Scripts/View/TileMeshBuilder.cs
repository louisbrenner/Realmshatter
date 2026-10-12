using System;
using Godot;

namespace Realmshatter;

/// <summary>
/// Builds the board as real geometry: one raised, chamfered stone block per tile with a small gap between the
/// blocks and a tiny random height / tilt so the surface reads as physical stones instead of a painted plane.
/// Vertex positions use the same local frame as the old flat surface (x/z centred, tile tops at y ~ 0), so the
/// board_surface shader keeps colouring the zone, deploy rows and crown field from the local position.
/// </summary>
public static class TileMeshBuilder
{
	/// <summary>Creates the tile mesh for a width x height board; 'lift' raises single tiles (e.g. the crown field).</summary>
	public static ArrayMesh Build(int width, int height, float tileSize, float gap, float bevel, float depth, int seed = 11,
		Func<int, int, float> lift = null)
	{
		var st = new SurfaceTool();
		st.Begin(Mesh.PrimitiveType.Triangles);
		var rng = new Random(seed);
		float half = tileSize * 0.5f - gap * 0.5f;
		for (int y = 0; y < height; y++)
		{
			for (int x = 0; x < width; x++)
			{
				float cx = (x - (width - 1) * 0.5f) * tileSize;
				float cz = (y - (height - 1) * 0.5f) * tileSize;
				// Tops sink slightly (never rise above y = 0 so highlights and pieces stay on top) and tilt a hair.
				float top = -(float)rng.NextDouble() * 0.012f + (lift?.Invoke(x, y) ?? 0f);
				float tiltX = ((float)rng.NextDouble() - 0.5f) * 0.008f;
				float tiltZ = ((float)rng.NextDouble() - 0.5f) * 0.008f;
				AddBlock(st, new Vector3(cx, top, cz), half, bevel, depth, tiltX, tiltZ);
			}
		}
		return st.Commit();
	}

	private static void AddBlock(SurfaceTool st, Vector3 c, float half, float bevel, float depth, float tiltX, float tiltZ)
	{
		float inner = half - bevel;
		float bevelY = c.Y - bevel * 0.55f;
		float bottom = -depth;
		float Lift(float dx, float dz) => dx * tiltX + dz * tiltZ - Mathf.Max(0f, 0.004f);

		// Top face (inset by the chamfer).
		Vector3 t00 = new Vector3(c.X - inner, c.Y + Lift(-inner, -inner), c.Z - inner);
		Vector3 t10 = new Vector3(c.X + inner, c.Y + Lift(inner, -inner), c.Z - inner);
		Vector3 t11 = new Vector3(c.X + inner, c.Y + Lift(inner, inner), c.Z + inner);
		Vector3 t01 = new Vector3(c.X - inner, c.Y + Lift(-inner, inner), c.Z + inner);
		// Chamfer foot (full size, a bit lower).
		Vector3 b00 = new Vector3(c.X - half, bevelY, c.Z - half);
		Vector3 b10 = new Vector3(c.X + half, bevelY, c.Z - half);
		Vector3 b11 = new Vector3(c.X + half, bevelY, c.Z + half);
		Vector3 b01 = new Vector3(c.X - half, bevelY, c.Z + half);
		// Bottom ring.
		Vector3 d00 = new Vector3(c.X - half, bottom, c.Z - half);
		Vector3 d10 = new Vector3(c.X + half, bottom, c.Z - half);
		Vector3 d11 = new Vector3(c.X + half, bottom, c.Z + half);
		Vector3 d01 = new Vector3(c.X - half, bottom, c.Z + half);

		Quad(st, t00, t10, t11, t01, Vector3.Up);
		Quad(st, b00, b10, t10, t00, new Vector3(0, 1, -1).Normalized());
		Quad(st, b10, b11, t11, t10, new Vector3(1, 1, 0).Normalized());
		Quad(st, b11, b01, t01, t11, new Vector3(0, 1, 1).Normalized());
		Quad(st, b01, b00, t00, t01, new Vector3(-1, 1, 0).Normalized());
		Quad(st, d00, d10, b10, b00, Vector3.Forward);
		Quad(st, d10, d11, b11, b10, Vector3.Right);
		Quad(st, d11, d01, b01, b11, Vector3.Back);
		Quad(st, d01, d00, b00, b01, Vector3.Left);
	}

	/// <summary>Adds a quad (a, b, c, d around the face) with an explicit normal; winding chosen to face the normal.</summary>
	private static void Quad(SurfaceTool st, Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 normal)
	{
		Vector3 faceNormal = (b - a).Cross(c - a);
		bool flip = faceNormal.Dot(normal) > 0f;
		Vector3[] tri1 = flip ? new[] { a, c, b } : new[] { a, b, c };
		Vector3[] tri2 = flip ? new[] { a, d, c } : new[] { a, c, d };
		foreach (Vector3 v in tri1)
		{
			st.SetNormal(normal);
			st.AddVertex(v);
		}
		foreach (Vector3 v in tri2)
		{
			st.SetNormal(normal);
			st.AddVertex(v);
		}
	}
}
