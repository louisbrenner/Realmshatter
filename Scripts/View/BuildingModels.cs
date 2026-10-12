using Godot;

namespace Realmshatter;

/// <summary>Small procedural 3D models of the buildings (sit on the piece token) and the construction scaffold.</summary>
public static class BuildingModels
{
	private static readonly Color Stone = new Color(0.62f, 0.59f, 0.54f);
	private static readonly Color StoneDark = new Color(0.42f, 0.4f, 0.37f);
	private static readonly Color Wood = new Color(0.48f, 0.31f, 0.17f);

	/// <summary>Model of a building type; tint = building colour, owner = owner colour (banner / band).</summary>
	public static Node3D Create(BuildingType type, Color tint, Color owner)
	{
		var root = new Node3D { Name = "Building" };
		switch (type)
		{
			case BuildingType.Turret:
				Add(root, new CylinderMesh { TopRadius = 0.2f, BottomRadius = 0.26f, Height = 0.5f, RadialSegments = 16 }, Mat(Stone), new Vector3(0, 0.25f, 0));
				Add(root, new CylinderMesh { TopRadius = 0.27f, BottomRadius = 0.27f, Height = 0.06f, RadialSegments = 16 }, Mat(owner, 0.6f), new Vector3(0, 0.3f, 0));
				Add(root, new CylinderMesh { TopRadius = 0.25f, BottomRadius = 0.23f, Height = 0.1f, RadialSegments = 16 }, Mat(StoneDark), new Vector3(0, 0.55f, 0));
				for (int i = 0; i < 6; i++)
				{
					float a = Mathf.Tau * i / 6f;
					Add(root, new BoxMesh { Size = new Vector3(0.08f, 0.09f, 0.08f) }, Mat(Stone), new Vector3(Mathf.Cos(a) * 0.2f, 0.64f, Mathf.Sin(a) * 0.2f));
				}
				Add(root, new BoxMesh { Size = new Vector3(0.05f, 0.14f, 0.2f) }, Mat(new Color(0.1f, 0.08f, 0.06f)), new Vector3(0.21f, 0.4f, 0), 0.6f);
				break;
			case BuildingType.ManaWell:
				Add(root, new CylinderMesh { TopRadius = 0.27f, BottomRadius = 0.3f, Height = 0.18f, RadialSegments = 20 }, Mat(Stone), new Vector3(0, 0.09f, 0));
				Add(root, new CylinderMesh { TopRadius = 0.21f, BottomRadius = 0.21f, Height = 0.02f, RadialSegments = 20 }, Glow(new Color(0.3f, 0.65f, 1f), 1.6f), new Vector3(0, 0.18f, 0));
				Add(root, new PrismMesh { Size = new Vector3(0.14f, 0.32f, 0.14f) }, Glow(new Color(0.45f, 0.75f, 1f), 2.4f), new Vector3(0, 0.36f, 0));
				Add(root, new PrismMesh { Size = new Vector3(0.14f, 0.2f, 0.14f) }, Glow(new Color(0.45f, 0.75f, 1f), 2.4f), new Vector3(0, 0.12f, 0), Mathf.Pi);
				break;
			case BuildingType.Shrine:
				Add(root, new BoxMesh { Size = new Vector3(0.44f, 0.08f, 0.44f) }, Mat(Stone), new Vector3(0, 0.04f, 0));
				Add(root, new CylinderMesh { TopRadius = 0.08f, BottomRadius = 0.1f, Height = 0.42f, RadialSegments = 12 }, Mat(new Color(0.9f, 0.86f, 0.75f)), new Vector3(0, 0.29f, 0));
				Add(root, new SphereMesh { Radius = 0.1f, Height = 0.2f }, Glow(new Color(1f, 0.85f, 0.4f), 2.6f), new Vector3(0, 0.6f, 0));
				break;
			case BuildingType.Barricade:
				for (int i = -1; i <= 1; i++)
				{
					Add(root, new CylinderMesh { TopRadius = 0.06f, BottomRadius = 0.06f, Height = 0.6f, RadialSegments = 8 }, Mat(Wood),
						new Vector3(i * 0.15f, 0.18f, 0), 0f, new Vector3(0.9f, 0, 0));
					Add(root, new CylinderMesh { TopRadius = 0f, BottomRadius = 0.05f, Height = 0.16f, RadialSegments = 8 }, Mat(new Color(0.75f, 0.7f, 0.62f)),
						new Vector3(i * 0.15f, 0.42f, -0.2f), 0f, new Vector3(0.9f, 0, 0));
				}
				Add(root, new BoxMesh { Size = new Vector3(0.5f, 0.08f, 0.08f) }, Mat(owner, 0.4f), new Vector3(0, 0.12f, 0.05f));
				break;
			case BuildingType.Obelisk:
				Add(root, new BoxMesh { Size = new Vector3(0.34f, 0.08f, 0.34f) }, Mat(StoneDark), new Vector3(0, 0.04f, 0));
				Add(root, new CylinderMesh { TopRadius = 0.05f, BottomRadius = 0.14f, Height = 0.8f, RadialSegments = 4 }, Mat(new Color(0.25f, 0.2f, 0.32f)), new Vector3(0, 0.48f, 0), Mathf.Pi / 4f);
				Add(root, new CylinderMesh { TopRadius = 0.012f, BottomRadius = 0.035f, Height = 0.7f, RadialSegments = 4 }, Glow(tint, 2.2f), new Vector3(0, 0.5f, 0.07f), Mathf.Pi / 4f);
				break;
		}
		return root;
	}

	/// <summary>Wooden scaffold shown while a building is under construction.</summary>
	public static Node3D CreateScaffold()
	{
		var root = new Node3D { Name = "Scaffold" };
		var pole = new CylinderMesh { TopRadius = 0.018f, BottomRadius = 0.018f, Height = 0.55f, RadialSegments = 6 };
		var bar = new BoxMesh { Size = new Vector3(0.6f, 0.025f, 0.025f) };
		StandardMaterial3D wood = Mat(new Color(0.62f, 0.45f, 0.26f));
		foreach (Vector2 c in new[] { new Vector2(-0.28f, -0.28f), new Vector2(0.28f, -0.28f), new Vector2(-0.28f, 0.28f), new Vector2(0.28f, 0.28f) })
		{
			Add(root, pole, wood, new Vector3(c.X, 0.27f, c.Y));
		}
		foreach (float y in new[] { 0.2f, 0.45f })
		{
			Add(root, bar, wood, new Vector3(0, y, -0.28f));
			Add(root, bar, wood, new Vector3(0, y, 0.28f));
			Add(root, bar, wood, new Vector3(-0.28f, y, 0), Mathf.Pi / 2f);
			Add(root, bar, wood, new Vector3(0.28f, y, 0), Mathf.Pi / 2f);
		}
		return root;
	}

	private static void Add(Node3D parent, Mesh mesh, Material mat, Vector3 pos, float yaw = 0f, Vector3? rotation = null)
	{
		parent.AddChild(new MeshInstance3D
		{
			Mesh = mesh,
			MaterialOverride = mat,
			Position = pos,
			Rotation = rotation ?? new Vector3(0, yaw, 0),
		});
	}

	private static StandardMaterial3D Mat(Color color, float emission = 0f) => new StandardMaterial3D
	{
		AlbedoColor = color,
		Roughness = 0.85f,
		EmissionEnabled = emission > 0f,
		Emission = color,
		EmissionEnergyMultiplier = emission,
	};

	private static StandardMaterial3D Glow(Color color, float energy) => new StandardMaterial3D
	{
		AlbedoColor = color,
		Roughness = 0.2f,
		EmissionEnabled = true,
		Emission = color,
		EmissionEnergyMultiplier = energy,
	};
}
