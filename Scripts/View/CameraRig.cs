using Godot;

namespace Realmshatter;

/// <summary>
/// Camera rig for the three view modes. The rig sits at the board center; its child Camera3D
/// is positioned around it. 2D = orthographic top-down, 2.5D = orthographic angled,
/// 3D = perspective angled. Player 0 (board +Z side) is always at the bottom of the screen.
/// Mode switches tween pitch, yaw, distance and ortho size / fov.
/// </summary>
public partial class CameraRig : Node3D
{
	/// <summary>Emitted when the view mode changes (value = (int)ViewMode).</summary>
	[Signal] public delegate void ViewModeChangedEventHandler(int mode);

	[Export] public ViewMode InitialMode { get; set; } = ViewMode.ThreeD;
	/// <summary>Board extent to fit in world units (X = width, Y = depth along Z).</summary>
	[Export] public Vector2 BoardFitSize { get; set; } = new Vector2(10, 8);
	/// <summary>Extra space around the board in world units.</summary>
	[Export] public float FitMargin { get; set; } = 0.55f;
	/// <summary>Height of pieces/labels to keep in view.</summary>
	[Export] public float ContentHeight { get; set; } = 0.5f;
	[Export] public float TweenDuration { get; set; } = 0.6f;

	[ExportGroup("Screen Insets")]
	/// <summary>Resolution the HUD is designed for; insets are given in these pixels and scale like the HUD.</summary>
	[Export] public Vector2 InsetReferenceSize { get; set; } = new Vector2(1152, 648);
	/// <summary>Screen space kept free for the HUD (reference pixels): left side panels.</summary>
	[Export] public float InsetLeft { get; set; } = 210f;
	/// <summary>Top bar + hint ribbon.</summary>
	[Export] public float InsetTop { get; set; } = 74f;
	/// <summary>Right column (deck, End Turn).</summary>
	[Export] public float InsetRight { get; set; } = 176f;
	/// <summary>Resting hand cards.</summary>
	[Export] public float InsetBottom { get; set; } = 104f;
	/// <summary>Lower bound of the HUD scale (must match Hud.MinScale).</summary>
	[Export] public float InsetMinScale { get; set; } = 0.7f;

	[ExportGroup("2D")]
	[Export] public float OrthoDistance { get; set; } = 30f;

	[ExportGroup("2.5D")]
	[Export] public float IsoPitchDegrees { get; set; } = -50f;
	[Export] public float IsoYawDegrees { get; set; } = 20f;

	[ExportGroup("3D")]
	[Export] public float PerspectivePitchDegrees { get; set; } = -66f;
	[Export] public float PerspectiveYawDegrees { get; set; } = 0f;
	[Export] public float PerspectiveFov { get; set; } = 50f;

	private Camera3D _camera;
	private Tween _tween;
	private CamPose _from;
	private CamPose _to;
	private CamPose _current;
	private bool _switchedProjection;
	private readonly RandomNumberGenerator _shakeRng = new RandomNumberGenerator();
	private float _shakeStrength;
	private float _shakeDuration;
	private float _shakeTime;
	private Vector2 _shakeOffset;

	/// <summary>Currently active (or target, while tweening) view mode.</summary>
	public ViewMode Mode { get; private set; }

	/// <summary>The rig's camera.</summary>
	public Camera3D Camera => _camera;

	private struct CamPose
	{
		public float Pitch;
		public float Yaw;
		public float Distance;
		public float Size;
		public float Fov;
		public Vector2 Offset;
		public bool Orthogonal;
	}

	public override void _Ready()
	{
		_camera = GetNode<Camera3D>("Camera3D");
		GetViewport().SizeChanged += OnViewportSizeChanged;
		SetMode(InitialMode, false);
	}

	public override void _ExitTree()
	{
		Viewport viewport = GetViewport();
		if (viewport != null)
		{
			viewport.SizeChanged -= OnViewportSizeChanged;
		}
	}

	/// <summary>Switches to a view mode, optionally with a tween.</summary>
	public void SetMode(ViewMode mode, bool animate = true)
	{
		if (_camera == null)
		{
			_camera = GetNode<Camera3D>("Camera3D");
		}
		Mode = mode;
		CamPose target = ComputePose(mode);

		if (_tween != null && _tween.IsValid())
		{
			_tween.Kill();
		}

		if (!animate || TweenDuration <= 0f)
		{
			_current = target;
			ApplyPose(target);
		}
		else
		{
			_from = _current;
			_to = target;
			_switchedProjection = false;
			_tween = CreateTween();
			_tween.SetTrans(Tween.TransitionType.Cubic).SetEase(Tween.EaseType.InOut);
			_tween.TweenMethod(Callable.From<float>(Blend), 0.0f, 1.0f, TweenDuration);
		}
		EmitSignal(SignalName.ViewModeChanged, (int)mode);
	}

	/// <summary>
	/// Shakes the camera for a moment (offset in world units along the screen axes, decaying).
	/// A stronger or longer running shake is not cut short by a weaker one.
	/// </summary>
	public void Shake(float strength, float duration)
	{
		if (strength <= 0f || duration <= 0f)
		{
			return;
		}
		float remaining = _shakeDuration > 0f ? _shakeStrength * Mathf.Max(0f, 1f - _shakeTime / _shakeDuration) : 0f;
		_shakeStrength = Mathf.Max(strength, remaining);
		_shakeDuration = duration;
		_shakeTime = 0f;
	}

	public override void _Process(double delta)
	{
		if (_camera == null || _shakeDuration <= 0f)
		{
			return;
		}
		_shakeTime += (float)delta;
		if (_shakeTime >= _shakeDuration)
		{
			_shakeDuration = 0f;
			_shakeOffset = Vector2.Zero;
		}
		else
		{
			float k = 1f - _shakeTime / _shakeDuration;
			float s = _shakeStrength * k * k;
			_shakeOffset = new Vector2(_shakeRng.RandfRange(-1f, 1f), _shakeRng.RandfRange(-1f, 1f)) * s;
		}
		if (_tween == null || !_tween.IsValid() || !_tween.IsRunning())
		{
			ApplyPose(_current);
		}
	}

	/// <summary>Advances 2D -> 2.5D -> 3D -> 2D and returns the new mode.</summary>
	public ViewMode CycleMode()
	{
		ViewMode next = Mode switch
		{
			ViewMode.TwoD => ViewMode.TwoPointFiveD,
			ViewMode.TwoPointFiveD => ViewMode.ThreeD,
			_ => ViewMode.TwoD,
		};
		SetMode(next, true);
		return next;
	}

	private void OnViewportSizeChanged()
	{
		if (_tween != null && _tween.IsValid() && _tween.IsRunning())
		{
			_to = ComputePose(Mode);
			return;
		}
		_current = ComputePose(Mode);
		ApplyPose(_current);
	}

	private void Blend(float t)
	{
		var pose = new CamPose
		{
			Pitch = Mathf.LerpAngle(_from.Pitch, _to.Pitch, t),
			Yaw = Mathf.LerpAngle(_from.Yaw, _to.Yaw, t),
			Distance = Mathf.Lerp(_from.Distance, _to.Distance, t),
			Size = Mathf.Lerp(_from.Size, _to.Size, t),
			Fov = Mathf.Lerp(_from.Fov, _to.Fov, t),
			Offset = _from.Offset.Lerp(_to.Offset, t),
			Orthogonal = _from.Orthogonal,
		};
		if (_from.Orthogonal != _to.Orthogonal && t >= 0.5f)
		{
			_switchedProjection = true;
		}
		if (_switchedProjection || t >= 1.0f)
		{
			pose.Orthogonal = _to.Orthogonal;
		}
		_current = pose;
		ApplyPose(pose);
	}

	private void ApplyPose(CamPose pose)
	{
		Basis basis = Basis.FromEuler(new Vector3(pose.Pitch, pose.Yaw, 0f));
		Vector3 forward = -basis.Z;
		Vector3 position = basis.X * (pose.Offset.X + _shakeOffset.X) + basis.Y * (pose.Offset.Y + _shakeOffset.Y) - forward * pose.Distance;
		_camera.Transform = new Transform3D(basis, position);
		_camera.KeepAspect = Camera3D.KeepAspectEnum.Height;
		if (pose.Orthogonal)
		{
			_camera.Projection = Camera3D.ProjectionType.Orthogonal;
			_camera.Size = Mathf.Max(0.1f, pose.Size);
		}
		else
		{
			_camera.Projection = Camera3D.ProjectionType.Perspective;
			_camera.Fov = Mathf.Clamp(pose.Fov, 1f, 170f);
		}
	}

	private CamPose ComputePose(ViewMode mode)
	{
		float aspect = GetAspect();
		switch (mode)
		{
			case ViewMode.TwoPointFiveD:
				return ComputeOrthoPose(Mathf.DegToRad(IsoPitchDegrees), Mathf.DegToRad(IsoYawDegrees), aspect);
			case ViewMode.ThreeD:
				return ComputePerspectivePose(Mathf.DegToRad(PerspectivePitchDegrees), Mathf.DegToRad(PerspectiveYawDegrees), aspect);
			default:
				return ComputeOrthoPose(Mathf.DegToRad(-90f), 0f, aspect);
		}
	}

	private CamPose ComputeOrthoPose(float pitch, float yaw, float aspect)
	{
		Basis basis = Basis.FromEuler(new Vector3(pitch, yaw, 0f));
		float minX = float.MaxValue, maxX = float.MinValue, minY = float.MaxValue, maxY = float.MinValue;
		foreach (Vector3 corner in GetFitCorners())
		{
			float x = corner.Dot(basis.X);
			float y = corner.Dot(basis.Y);
			minX = Mathf.Min(minX, x);
			maxX = Mathf.Max(maxX, x);
			minY = Mathf.Min(minY, y);
			maxY = Mathf.Max(maxY, y);
		}
		float spanX = maxX - minX;
		float spanY = maxY - minY;
		GetInsetFractions(out float left, out float top, out float right, out float bottom);
		float availX = Mathf.Max(0.2f, 1f - left - right);
		float availY = Mathf.Max(0.2f, 1f - top - bottom);
		float size = Mathf.Max(spanY / availY, spanX / (Mathf.Max(0.1f, aspect) * availX));
		// Shift so the board is centered in the screen area left free by the HUD.
		float shiftX = (left - right) * 0.5f * size * aspect;
		float shiftY = (bottom - top) * 0.5f * size;
		return new CamPose
		{
			Pitch = pitch,
			Yaw = yaw,
			Distance = OrthoDistance,
			Size = size,
			Fov = PerspectiveFov,
			Offset = new Vector2((minX + maxX) * 0.5f - shiftX, (minY + maxY) * 0.5f - shiftY),
			Orthogonal = true,
		};
	}

	private CamPose ComputePerspectivePose(float pitch, float yaw, float aspect)
	{
		Basis basis = Basis.FromEuler(new Vector3(pitch, yaw, 0f));
		Vector3 forward = -basis.Z;
		float tanV = Mathf.Tan(Mathf.DegToRad(PerspectiveFov) * 0.5f);
		float tanH = tanV * Mathf.Max(0.1f, aspect);
		GetInsetFractions(out float left, out float top, out float right, out float bottom);
		float fitV = tanV * Mathf.Max(0.2f, 1f - top - bottom);
		float fitH = tanH * Mathf.Max(0.2f, 1f - left - right);
		float distance = 1f;
		foreach (Vector3 corner in GetFitCorners())
		{
			float x = Mathf.Abs(corner.Dot(basis.X));
			float y = Mathf.Abs(corner.Dot(basis.Y));
			float depthOffset = corner.Dot(forward);
			distance = Mathf.Max(distance, y / fitV - depthOffset);
			distance = Mathf.Max(distance, x / fitH - depthOffset);
		}
		// Slide the camera sideways so the board center lands in the middle of the free screen area.
		var offset = new Vector2(-(left - right) * tanH * distance, -(bottom - top) * tanV * distance);
		return new CamPose
		{
			Pitch = pitch,
			Yaw = yaw,
			Distance = distance,
			Size = BoardFitSize.Y + FitMargin * 2f,
			Fov = PerspectiveFov,
			Offset = offset,
			Orthogonal = false,
		};
	}

	private Vector3[] GetFitCorners()
	{
		float hx = BoardFitSize.X * 0.5f + FitMargin;
		float hz = BoardFitSize.Y * 0.5f + FitMargin;
		float h = ContentHeight;
		return new[]
		{
			new Vector3(-hx, 0, -hz), new Vector3(hx, 0, -hz), new Vector3(-hx, 0, hz), new Vector3(hx, 0, hz),
			new Vector3(-hx, h, -hz), new Vector3(hx, h, -hz), new Vector3(-hx, h, hz), new Vector3(hx, h, hz),
		};
	}

	/// <summary>HUD insets as fractions of the viewport (scaled like the HUD: min(w/refW, h/refH)).</summary>
	private void GetInsetFractions(out float left, out float top, out float right, out float bottom)
	{
		Vector2 size = GetViewport().GetVisibleRect().Size;
		if (size.X <= 0f || size.Y <= 0f || InsetReferenceSize.X <= 0f || InsetReferenceSize.Y <= 0f)
		{
			left = top = right = bottom = 0f;
			return;
		}
		float scale = Mathf.Max(InsetMinScale, Mathf.Min(size.X / InsetReferenceSize.X, size.Y / InsetReferenceSize.Y));
		left = InsetLeft * scale / size.X;
		right = InsetRight * scale / size.X;
		top = InsetTop * scale / size.Y;
		bottom = InsetBottom * scale / size.Y;
	}

	private float GetAspect()
	{
		Vector2 size = GetViewport().GetVisibleRect().Size;
		return size.Y > 0f ? size.X / size.Y : 16f / 9f;
	}
}
