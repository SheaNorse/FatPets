using Godot;
using System;
using System.Runtime.InteropServices;

public partial class DesktopPet : Node
{
	[DllImport("user32.dll")]
	static extern int GetWindowLong(IntPtr hWnd, int nIndex);
	
	[DllImport("user32.dll")]
	static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
	
	[DllImport("user32.dll")]
	static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
	
	[DllImport("user32.dll")]
	static extern bool SystemParametersInfo(int uAction, int uParam, ref RECT lpvParam, int fuWinIni);
	
	[DllImport("user32.dll")]
	static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
	
	[DllImport("user32.dll")]
	static extern bool GetWindowRect(IntPtr hWnd, ref RECT lpRect);
	
	[DllImport("user32.dll")]
	static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);
	
	[DllImport("user32.dll")]
	static extern bool SetForegroundWindow(IntPtr hWnd);

	[DllImport("user32.dll")]
	static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
	
	[DllImport("user32.dll")]
	static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);

	private const uint RDW_INVALIDATE = 0x0001;
	private const uint RDW_UPDATENOW  = 0x0100;
	private const uint RDW_ALLCHILDREN = 0x0080;

	private const int SW_RESTORE = 9;
	
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
	public struct POINT
	{
		public int X;
		public int Y;
	}
	
	const int SPI_GETWORKAREA = 0x0030;
	const int GWL_EXSTYLE = -20;
	const int WS_EX_LAYERED = 0x80000;
	const int WS_EX_TRANSPARENT = 0x20;
	const uint SWP_FRAMECHANGED = 0x0020;
	const uint SWP_NOMOVE = 0x0002;
	const uint SWP_NOSIZE = 0x0001;
	const uint SWP_NOZORDER = 0x0004;
	const uint SWP_NOACTIVATE = 0x0010;
	const uint MONITOR_DEFAULTTONEAREST = 2;
	
	private IntPtr _hwnd;
	
	public override void _Ready()
	{
		_hwnd = (IntPtr)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
		GetTree().Root.TransparentBg = true;
		
		SetClickThrough(true);
		DisplayServer.WindowSetFlag(DisplayServer.WindowFlags.AlwaysOnTop, true);
	}
	
	private bool _isCurrentClickThrough = false;

	// Inside DesktopPet.cs
	private bool? _isClickThroughEnabled = null; // Use nullable to force first set

	public void SetClickThrough(bool enabled)
	{
		// 1. Same logic as before: prevent redundant calls
		if (_isClickThroughEnabled == enabled) return;
		_isClickThroughEnabled = enabled;

		int currentStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
		int newStyle = enabled
			? (currentStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT)
			: ((currentStyle | WS_EX_LAYERED) & ~WS_EX_TRANSPARENT);

		if (currentStyle != newStyle)
		{
			SetWindowLong(_hwnd, GWL_EXSTYLE, newStyle);
			
			// STANDARD FLICKER-FREE UPDATE: Use RedrawWindow for normal hovers
			RedrawWindow(_hwnd, IntPtr.Zero, IntPtr.Zero, 0x0001 | 0x0100 | 0x0080);
		}
	}
		
	public RECT GetTaskbarInfo()
	{
		RECT rect = new RECT();
		IntPtr taskbarHandle = FindWindow("Shell_TrayWnd", null);
		if (taskbarHandle != IntPtr.Zero)
		{
			GetWindowRect(taskbarHandle, ref rect);
		}
		return rect;
	}
	
	public RECT GetWorkArea()
	{
		RECT rect = new RECT();
		SystemParametersInfo(SPI_GETWORKAREA, 0, ref rect, 0);
		return rect;
	}
	
	public int GetFloorPosition()
	{
		var workArea = GetWorkArea();
		return workArea.Bottom;
	}
	
	public int GetFloorPositionAtPoint(int x, int y)
	{
		var workArea = GetWorkArea();
		return workArea.Bottom;
	}
	
	public int GetTaskbarHeight()
	{
		var taskbarRect = GetTaskbarInfo();
		if (taskbarRect.Height > 0)
		{
			return taskbarRect.Height;
		}
		return 48; // Default fallback
	}
	
	public bool IsTaskbarOnScreen(int screenIndex)
	{
		var taskbarRect = GetTaskbarInfo();
		var screenPos = DisplayServer.ScreenGetPosition(screenIndex);
		var screenSize = DisplayServer.ScreenGetSize(screenIndex);
		
		// Check if taskbar intersects with this screen
		bool intersects = !(taskbarRect.Right < screenPos.X || 
							taskbarRect.Left > screenPos.X + screenSize.X ||
							taskbarRect.Bottom < screenPos.Y || 
							taskbarRect.Top > screenPos.Y + screenSize.Y);
		
		return intersects;
	}
	
	public void ForceInputMapUpdate()
	{
		// SWP_FRAMECHANGED tells the OS: "The window definition changed, recalculate where clicks go!"
		SetWindowPos(_hwnd, IntPtr.Zero, 0, 0, 0, 0, 
			SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
	}

	public async void MoveToScreen(int screenIndex)
	{
		if (screenIndex < 0 || screenIndex >= DisplayServer.GetScreenCount()) return;

		SetClickThrough(false);
		
		// 1. Move and Resize
		DisplayServer.WindowSetCurrentScreen(screenIndex);
		Vector2I screenSize = DisplayServer.ScreenGetSize(screenIndex);
		DisplayServer.WindowSetSize(screenSize);
		
		// 2. IMPORTANT: Re-verify Godot's internal transparency
		GetTree().Root.TransparentBg = true;

		// 3. Give the OS a moment to settle the new window bounds
		await ToSignal(GetTree().CreateTimer(0.2), SceneTreeTimer.SignalName.Timeout);

		// 4. Force Windows to re-apply the Layered attribute
		// This often clears the "Black Box" issue
		int currentStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
		SetWindowLong(_hwnd, GWL_EXSTYLE, currentStyle | WS_EX_LAYERED);
		
		_isClickThroughEnabled = null; 
		SetClickThrough(true);
		ForceInputMapUpdate();
		
		// 5. Final Paint Call
		RedrawWindow(_hwnd, IntPtr.Zero, IntPtr.Zero, RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
	}
	
	public int GetScreenCount()
	{
		return DisplayServer.GetScreenCount();
	}
	
	public RECT GetWorkAreaForScreen(int screenIndex)
	{
		int currentScreen = DisplayServer.WindowGetCurrentScreen();
		DisplayServer.WindowSetCurrentScreen(screenIndex);
		
		RECT workArea = GetWorkArea();
		
		DisplayServer.WindowSetCurrentScreen(currentScreen);
		
		return workArea;
	}
	private int _hoveredPetsCount = 0;

	public void ReportHoverState(bool isHovering)
	{
		if (isHovering) _hoveredPetsCount++;
		else _hoveredPetsCount--;

		// Clamp to ensure it doesn't go below 0
		_hoveredPetsCount = Math.Max(0, _hoveredPetsCount);

		// If even one pet is hovered, the window must be solid
		SetClickThrough(_hoveredPetsCount == 0);
	}
}
