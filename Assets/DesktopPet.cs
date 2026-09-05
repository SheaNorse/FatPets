using Godot;
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public partial class DesktopPet : Node
{
	// --- Static Tracking Counters ---
	private static int _petCount = 0;
	private static int _foodCount = 0;

	public static void RegisterPet()
	{
		_petCount++;
		GD.Print($"Pet added. Total pets: {_petCount}");
	}

	public static void UnregisterPet(SceneTree tree)
	{
		_petCount--;
		GD.Print($"Pet removed. Total pets: {_petCount}");
		CheckRemainingElements(tree);
	}

	public static void RegisterFood()
	{
		_foodCount++;
		GD.Print($"Food added. Total food: {_foodCount}");
	}

	public static void UnregisterFood(SceneTree tree)
	{
		_foodCount--;
		GD.Print($"Food removed. Total food: {_foodCount}");
		CheckRemainingElements(tree);
	}

	private static void CheckRemainingElements(SceneTree tree)
	{
		if (_petCount <= 0 && _foodCount <= 0)
		{
			GD.Print("No pets or food remaining! Automatically exiting application...");
			tree.Quit();
		}
	}

	// ------------------------------------
	// --- Win32 Native Imports ---
	[DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
	[DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
	[DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
	[DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

	[DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
	[DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS pMarInset);

	// --- Taskbar detection (auto-hide aware) ---
	[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
	static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

	[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
	static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string lpszWindow);

	[DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

	[DllImport("user32.dll")]
	static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

	[DllImport("user32.dll")]
	static extern IntPtr MonitorFromRect(ref RECT lprc, uint dwFlags);

	const int GWL_EXSTYLE = -20;
	const int WS_EX_LAYERED = 0x80000;
	const int WS_EX_TRANSPARENT = 0x20;

	// SWP Flags with Anti-Flicker Guards
	const uint SWP_NOSIZE = 0x0001;
	const uint SWP_NOMOVE = 0x0002;
	const uint SWP_NOZORDER = 0x0004;
	const uint SWP_NOREDRAW = 0x0008;      // Prevents redrawing default frame background
	const uint SWP_NOACTIVATE = 0x0010;
	const uint SWP_FRAMECHANGED = 0x0020;
	const uint SWP_DEFERERASE = 0x2000;     // Prevents WM_ERASEBKGND white flash

	const uint MONITOR_DEFAULTTONEAREST = 2;

	// ShowWindow Commands
	const int SW_HIDE = 0;
	const int SW_SHOWNOACTIVATE = 4;

	// DWM Anti-Flash Attributes
	const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
	const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;

	private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

	private const string TaskbarClassPrimary = "Shell_TrayWnd";
	private const string TaskbarClassSecondary = "Shell_SecondaryTrayWnd";

	[StructLayout(LayoutKind.Sequential)]
	public struct RECT
	{
		public int Left;
		public int Top;
		public int Right;
		public int Bottom;

		public int Width => Right - Left;
		public int Height => Bottom - Top;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct MARGINS
	{
		public int cxLeftWidth;
		public int cxRightWidth;
		public int cyTopHeight;
		public int cyBottomHeight;
	}

	private IntPtr _hwnd;
	private bool? _isClickThroughEnabled = null;
	private readonly HashSet<string> _hoveredObjects = new HashSet<string>();
	private readonly bool _isWindows = OS.GetName() == "Windows";

	private readonly List<IntPtr> _taskbarWindows = new List<IntPtr>();
	private double _taskbarRefreshTimer = 0.0;
	private const double TaskbarRefreshIntervalSeconds = 1.0;

	private double _topMostRefreshTimer = 0.0;
	private const double TopMostRefreshIntervalSeconds = 2.0;

	// --- Manual floor offset (fallback ONLY) ---
	[Export] public int FloorOffsetPixels = 48;

	// Cushion above auto-hidden taskbar
	[Export] public int TaskbarRevealMarginPixels = 4;

	// --- Hover debounce (anti-flicker) ---
	private const float HoverDebounceSeconds = 0.05f;
	private SceneTreeTimer _hoverDebounceTimer;

	// --- Screen-enter fade tween ---
	[Export] public float ScreenEnterFadeDurationSeconds = 0.4f;
	[Export] public Tween.TransitionType ScreenEnterFadeTransition = Tween.TransitionType.Sine;
	[Export] public Tween.EaseType ScreenEnterFadeEase = Tween.EaseType.Out;

	public override async void _Ready()
	{
		_hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);

		// 1. Hide actual OS window handle before DWM composition links
		if (_isWindows && _hwnd != IntPtr.Zero)
		{
			ShowWindow(_hwnd, SW_HIDE);
		}

		ApplyAntiFlashAttributes();

		GetTree().Root.TransparentBg = true;
		DisplayServer.WindowSetFlag(DisplayServer.WindowFlags.AlwaysOnTop, true);

		// Pre-hide all pet sprites instantly so they are 100% transparent before window reveals
		HideAllPetsInitially();

		// 2. Yield two frames for Godot frame buffers and DWM transparent surface sync
		await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
		await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

		if (!GodotObject.IsInstanceValid(this)) return;

		// 3. Unhide HWND without stealing window focus
		if (_isWindows && _hwnd != IntPtr.Zero)
		{
			ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
		}

		RefreshTaskbarWindows();

		// 4. Force immediate click-through + frame update on startup so Windows registers hit-testing
		SetClickThrough(true, forceFrameRefresh: true);
		ForceTopMost();

		// 5. Place pets and launch the smooth alpha fade-in tween
		RandomizeInitialPetPositions();
	}

	public override void _Process(double delta)
	{
		_taskbarRefreshTimer += delta;
		if (_taskbarRefreshTimer >= TaskbarRefreshIntervalSeconds)
		{
			_taskbarRefreshTimer = 0.0;
			RefreshTaskbarWindows();
		}

		_topMostRefreshTimer += delta;
		if (_topMostRefreshTimer >= TopMostRefreshIntervalSeconds)
		{
			_topMostRefreshTimer = 0.0;
			ForceTopMost();
		}
	}

	private void ApplyAntiFlashAttributes()
	{
		if (!_isWindows || _hwnd == IntPtr.Zero) return;

		// Force dark titlebar/frame context to avoid white background flushes
		int useDarkMode = 1;
		DwmSetWindowAttribute(_hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref useDarkMode, sizeof(int));

		// Disable rounded corner flash artifacts
		int cornerPreference = 1; // DWMSW_DONOTROUND
		DwmSetWindowAttribute(_hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref cornerPreference, sizeof(int));

		// Force DWM frame extension to map transparency across full HWND canvas
		MARGINS margins = new MARGINS { cxLeftWidth = -1, cxRightWidth = -1, cyTopHeight = -1, cyBottomHeight = -1 };
		DwmExtendFrameIntoClientArea(_hwnd, ref margins);
	}

	private void RefreshTaskbarWindows()
	{
		_taskbarWindows.Clear();
		if (!_isWindows) return;

		IntPtr primary = FindWindow(TaskbarClassPrimary, null);
		if (primary != IntPtr.Zero) _taskbarWindows.Add(primary);

		IntPtr secondary = IntPtr.Zero;
		while (true)
		{
			secondary = FindWindowEx(IntPtr.Zero, secondary, TaskbarClassSecondary, null);
			if (secondary == IntPtr.Zero) break;
			_taskbarWindows.Add(secondary);
		}
	}

	public void ForceTopMost()
	{
		if (!_isWindows || _hwnd == IntPtr.Zero) return;

		SetWindowPos(
			_hwnd,
			HWND_TOPMOST,
			0, 0, 0, 0,
			SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOREDRAW | SWP_DEFERERASE
		);
	}

	public void SetClickThrough(bool enabled, bool forceFrameRefresh = false)
	{
		if (_isClickThroughEnabled == enabled && !forceFrameRefresh) return;
		_isClickThroughEnabled = enabled;

		int currentStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
		int newStyle = enabled
			? (currentStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT)
			: ((currentStyle | WS_EX_LAYERED) & ~WS_EX_TRANSPARENT);

		if (currentStyle != newStyle || forceFrameRefresh)
		{
			SetWindowLong(_hwnd, GWL_EXSTYLE, newStyle);

			SetWindowPos(_hwnd, IntPtr.Zero, 0, 0, 0, 0,
				SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOREDRAW | SWP_DEFERERASE);
		}
	}

	public void ReportHoverState(bool isHovering, string objectId)
	{
		if (isHovering)
			_hoveredObjects.Add(objectId);
		else
			_hoveredObjects.Remove(objectId);

		_hoverDebounceTimer?.Dispose();
		_hoverDebounceTimer = GetTree().CreateTimer(HoverDebounceSeconds);
		_hoverDebounceTimer.Timeout += () =>
		{
			if (!GodotObject.IsInstanceValid(this)) return;

			SetClickThrough(_hoveredObjects.Count == 0);
			if (_hoveredObjects.Count == 0)
				ForceTopMost();
		};
	}

	public void ClearAllHoverStates()
	{
		_hoveredObjects.Clear();
		_hoverDebounceTimer?.Dispose();
		SetClickThrough(true);
		ForceTopMost();
	}

	public void SetFloorOffset(int pixels)
	{
		FloorOffsetPixels = Mathf.Max(0, pixels);
	}

	public RECT GetScreenRect(int screenIndex)
	{
		Vector2I screenPos = DisplayServer.ScreenGetPosition(screenIndex);
		Vector2I screenSize = DisplayServer.ScreenGetSize(screenIndex);

		return new RECT
		{
			Left = screenPos.X,
			Top = screenPos.Y,
			Right = screenPos.X + screenSize.X,
			Bottom = screenPos.Y + screenSize.Y
		};
	}

	public int GetFloorPosition()
	{
		int currentScreen = DisplayServer.WindowGetCurrentScreen();
		return GetFloorPositionForScreen(currentScreen);
	}

	public int GetFloorPositionForScreen(int screenIndex)
	{
		RECT screenRect = GetScreenRect(screenIndex);
		int? floor = TryGetTaskbarAdjustedFloor(screenRect, screenIndex);
		return floor ?? (screenRect.Bottom - Math.Max(1, FloorOffsetPixels));
	}

	private int? TryGetTaskbarAdjustedFloor(RECT screenRect, int screenIndex)
	{
		if (!_isWindows || _taskbarWindows.Count == 0) return null;

		const int edgeEpsilon = 8;
		RECT screenRectCopy = screenRect;
		IntPtr targetMonitor = MonitorFromRect(ref screenRectCopy, MONITOR_DEFAULTTONEAREST);

		foreach (IntPtr hwnd in _taskbarWindows)
		{
			if (!GetWindowRect(hwnd, out RECT tb)) continue;

			IntPtr taskbarMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
			bool sameMonitor = taskbarMonitor == targetMonitor && taskbarMonitor != IntPtr.Zero;

			int overlapLeft = Math.Max(tb.Left, screenRect.Left);
			int overlapRight = Math.Min(tb.Right, screenRect.Right);
			int overlapTop = Math.Max(tb.Top, screenRect.Top);
			int overlapBottom = Math.Min(tb.Bottom, screenRect.Bottom);
			bool overlaps = overlapRight > overlapLeft && overlapBottom > overlapTop;

			if (!sameMonitor && !overlaps) continue;

			bool dockedBottom = Math.Abs(tb.Bottom - screenRect.Bottom) <= edgeEpsilon && tb.Width >= tb.Height;
			if (!dockedBottom) continue;

			int margin = (tb.Height <= 12) ? TaskbarRevealMarginPixels : 0;
			int floor = tb.Top - margin;
			return Mathf.Clamp(floor, screenRect.Top, screenRect.Bottom);
		}

		Rect2I usable = DisplayServer.ScreenGetUsableRect(screenIndex);
		int usableBottom = usable.Position.Y + usable.Size.Y;

		if (usableBottom < screenRect.Bottom - 2)
			return usableBottom;

		return screenRect.Bottom - 1;
	}

	public int GetFloorPositionAtPoint(int x, int y)
	{
		int screenCount = DisplayServer.GetScreenCount();
		for (int i = 0; i < screenCount; i++)
		{
			RECT rect = GetScreenRect(i);
			if (x >= rect.Left && x < rect.Right && y >= rect.Top && y < rect.Bottom)
				return GetFloorPositionForScreen(i);
		}
		return GetFloorPosition();
	}

	public void ForceInputMapUpdate()
	{
		SetWindowPos(_hwnd, IntPtr.Zero, 0, 0, 0, 0,
			SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOREDRAW | SWP_DEFERERASE);
	}

	public void RandomizePetPosition(Node2D petNode, int screenIndex = -1)
	{
		if (!GodotObject.IsInstanceValid(petNode)) return;

		if (screenIndex < 0)
			screenIndex = DisplayServer.WindowGetCurrentScreen();

		Vector2I screenSize = DisplayServer.ScreenGetSize(screenIndex);
		Vector2I screenPos = DisplayServer.ScreenGetPosition(screenIndex);

		float paddingX = 100.0f;
		float minX = paddingX;
		float maxX = Math.Max(minX + 10.0f, screenSize.X - paddingX);

		int globalFloorY = GetFloorPositionForScreen(screenIndex);
		int localFloorY = globalFloorY - screenPos.Y;

		float minY = 50.0f;
		float maxY = Math.Max(minY + 10.0f, localFloorY - FloorOffsetPixels);

		float randomX = (float)GD.RandRange(minX, maxX);
		float randomY = (float)GD.RandRange(minY, maxY);

		petNode.GlobalPosition = new Vector2(randomX, randomY);

		// Reset movement velocities if properties exist
		petNode.Set("vertical_velocity", 0.0f);
		petNode.Set("horizontal_velocity", 0.0f);

		PlayScreenEnterFade(petNode);
	}

	private void PlayScreenEnterFade(Node2D petNode)
	{
		if (!GodotObject.IsInstanceValid(petNode)) return;

		// Force starting alpha to zero before starting the fade tween
		Color startColor = petNode.Modulate;
		startColor.A = 0.0f;
		petNode.Modulate = startColor;

		Tween tween = petNode.CreateTween();
		tween.TweenProperty(petNode, "modulate:a", 1.0f, ScreenEnterFadeDurationSeconds)
			.SetTrans(ScreenEnterFadeTransition)
			.SetEase(ScreenEnterFadeEase);
	}

	/// <summary>
	/// Immediately sets alpha of all detected pets to 0 prior to rendering window
	/// </summary>
	private void HideAllPetsInitially()
	{
		List<Node2D> pets = new List<Node2D>();
		FindPetsRecursive(GetTree().Root, pets);

		foreach (Node2D petNode in pets)
		{
			Color hidden = petNode.Modulate;
			hidden.A = 0.0f;
			petNode.Modulate = hidden;
		}
	}

	private void RandomizeInitialPetPositions()
	{
		int currentScreen = DisplayServer.WindowGetCurrentScreen();
		List<Node2D> pets = new List<Node2D>();

		FindPetsRecursive(GetTree().Root, pets);

		foreach (Node2D petNode in pets)
		{
			RandomizePetPosition(petNode, currentScreen);
		}
	}

	private void FindPetsRecursive(Node parent, List<Node2D> petList)
	{
		foreach (Node child in parent.GetChildren())
		{
			if (child != this && child is Node2D node2D && (child.IsInGroup("Pets") || child is CharacterBody2D))
			{
				petList.Add(node2D);
			}

			FindPetsRecursive(child, petList);
		}
	}

	public async void SwitchToScreen(int screenIndex, Node2D petNode = null)
	{
		int screenCount = DisplayServer.GetScreenCount();
		if (screenIndex < 0 || screenIndex >= screenCount) return;

		if (GodotObject.IsInstanceValid(petNode))
		{
			Color hiddenColor = petNode.Modulate;
			hiddenColor.A = 0.0f;
			petNode.Modulate = hiddenColor;
		}

		if (_isWindows && _hwnd != IntPtr.Zero)
		{
			ShowWindow(_hwnd, SW_HIDE);
		}

		if (!GetTree().Root.TransparentBg)
			GetTree().Root.TransparentBg = true;

		SetClickThrough(false);

		DisplayServer.WindowSetCurrentScreen(screenIndex);

		Vector2I screenSize = DisplayServer.ScreenGetSize(screenIndex);
		Vector2I screenPos = DisplayServer.ScreenGetPosition(screenIndex);

		DisplayServer.WindowSetSize(screenSize);
		DisplayServer.WindowSetPosition(screenPos);

		ApplyAntiFlashAttributes();

		await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
		await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);

		if (!GodotObject.IsInstanceValid(this)) return;

		if (_isWindows && _hwnd != IntPtr.Zero)
		{
			ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
		}

		int currentStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
		if ((currentStyle & WS_EX_LAYERED) == 0)
		{
			SetWindowLong(_hwnd, GWL_EXSTYLE, currentStyle | WS_EX_LAYERED);
		}

		_isClickThroughEnabled = null;
		SetClickThrough(true, forceFrameRefresh: true);
		ForceInputMapUpdate();
		ForceTopMost();

		RefreshTaskbarWindows();

		if (GodotObject.IsInstanceValid(petNode))
		{
			float randomDelay = (float)GD.RandRange(0.001, 0.3);
			await ToSignal(GetTree().CreateTimer(randomDelay), SceneTreeTimer.SignalName.Timeout);

			if (GodotObject.IsInstanceValid(this) && GodotObject.IsInstanceValid(petNode))
			{
				RandomizePetPosition(petNode, screenIndex);
			}
		}
	}

	public int GetScreenCount()
	{
		return DisplayServer.GetScreenCount();
	}
}
