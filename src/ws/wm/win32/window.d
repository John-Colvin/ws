module ws.wm.win32.window;

version(Windows):

import
	std.conv,
	std.string,
	std.utf,

	ws.string,
	ws.list,
	ws.gui.base,
	ws.draw,
	ws.wm.win32.api,
	ws.wm.win32.wm,
	ws.wm;

__gshared:


class Win32Window: Base {

	package {
		Mouse.cursor cursor = Mouse.cursor.inherit;
		string title;
		WindowHandle windowHandle;
		GraphicsContext graphicsContext;
		List!Event eventQueue;

		int antiAliasing = 1;
		HDC deviceContext;

		alias CB = void delegate(Event);
		CB[int] eventHandlers;

		int lastX, lastY, jumpX, jumpY;

		bool hasMouse;
		bool _hasFocus;
		
	}

	this(WindowHandle handle){
		windowHandle = handle;
	}

	this(int w, int h, string t){
		initializeHandlers;
		title = t;
		size = [w, h];
		eventQueue = new List!Event;
		RECT targetSize = {0, 0, size.x, size.y};
		AdjustWindowRect(&targetSize, WS_OVERLAPPEDWINDOW | WS_VISIBLE, false);
		windowHandle = CreateWindowExW(
			0, wm.windowClass.lpszClassName, title.toUTF16z(),
			WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
			targetSize.right-targetSize.left, targetSize.bottom-targetSize.top,
			null, null, wm.getInstance, null
		);
		if(!windowHandle)
			throw new Exception("CreateWindowW failed");
		RECT r;
		GetWindowRect(windowHandle, &r);
		pos = [r.left, r.right];

		shouldCreateGraphicsContext();
		drawInit;
		show();

		RAWINPUTDEVICE rawMouseDevice;
		rawMouseDevice.usUsagePage = 0x01; 
		rawMouseDevice.usUsage = 0x02;
		rawMouseDevice.dwFlags = RIDEV_INPUTSINK;   
		rawMouseDevice.hwndTarget = windowHandle;
		if(!RegisterRawInputDevices(&rawMouseDevice, 1, RAWINPUTDEVICE.sizeof))
			throw new Exception("Failed to register RID");
		
	}

	@property
	WindowHandle handle(){
		return windowHandle;
	}

	override void show(){
		if(!hidden)
			return;
		ShowWindow(windowHandle, SW_SHOWNORMAL);
		UpdateWindow(windowHandle);
		activateGraphicsContext();
		onKeyboardFocus(true);
		super.show;
	}

	override void hide(){
		if(hidden)
			return;
		DestroyWindow(windowHandle);
		super.hide;
	}

	override void resize(int[2] size){
		super.resize(size);
		glViewport(0,0,size.w,size.h);
		if(draw)
			draw.resize(size);
	}

	void setTitle(string title){
		this.title = title;
		if(!hidden)
			SetWindowTextW(windowHandle, title.toUTF16z());
	}

	string getTitle(){
		wchar[512] str;
		int r = GetWindowTextW(windowHandle, str.ptr, str.length);
		return to!string(str[0..r]);
	}

	long getPid(){
		DWORD pid;
		DWORD threadId = GetWindowThreadProcessId(windowHandle, &pid);
		return pid;
	}
	
	@property
	override bool hasFocus(){
		return _hasFocus;
	}
	
	override void onKeyboardFocus(bool focus){
		_hasFocus = focus;
	}
	
	void createGraphicsContext(){
		deviceContext = GetDC(windowHandle);
		if(!deviceContext)
			throw new Exception("window.Show failed: GetDC");
		uint formatCount = 0;
		int pixelFormat;
		int[] iAttribList = [
			0x2001, true,
			0x2010, true,
			0x2011, true,
			0x2003, 0x2027,
			0x2014, 0x202B,
			0x2014, 24,
			0x201B, 8,
			0x2022, 16,
			0x2023, 8,
			0x2011, true,
			0x2041, antiAliasing > 1 ? true : false,
			0x2042, antiAliasing,
			0
		];
		wm.wglChoosePixelFormatARB(deviceContext, iAttribList.ptr, null, 1, &pixelFormat, &formatCount);
		if(!formatCount)
			throw new Exception(tostring("wglChoosePixelFormatARB failed: ", glGetError()));
		SetPixelFormat(deviceContext, pixelFormat, null);
		int[] attribs = [
			0x2091, 3,
			0x2092, 2,
			0x9126, 0x00000001,
			0
		];
		graphicsContext = wm.wglCreateContextAttribsARB(deviceContext, null, attribs.ptr);
		if(!graphicsContext)
			throw new Exception(tostring("wglCreateContextAttribsARB() failed: ", glGetError()));
	}

	void createGraphicsContextOld(){
		PIXELFORMATDESCRIPTOR pfd = {
			(PIXELFORMATDESCRIPTOR).sizeof, 1, 4 | 32 | 1, 0, 8, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 0, 0, 0, 0, 0, 0
		};
		int pixelFormat = ChoosePixelFormat(deviceContext, &pfd);
		SetPixelFormat(deviceContext, pixelFormat, &pfd);
		graphicsContext = core.sys.windows.wingdi.wglCreateContext(deviceContext);
		wglMakeCurrent(deviceContext, graphicsContext);
	}

	void shouldCreateGraphicsContext(){
		try
			createGraphicsContext();
		catch
			createGraphicsContextOld();
		activateGraphicsContext();
		DerelictGL3.reload();
	}

	void makeCurrent(Context context){
		if(!wglMakeCurrent(deviceContext, context))
			throw new Exception("Failed to activate context, " ~ getLastError());
	}

	void activateGraphicsContext(){
		if(!wm.activeWindow)
			wm.activeWindow = this;
		makeCurrent(graphicsContext);
	}

	Context gcShare(){
		auto c = wm.wglCreateContextAttribsARB(deviceContext, graphicsContext, null);
		if(!c)
			throw new Exception("Failed to create shared context, " ~ getLastError());
		return c;
	}

	void swapBuffers(){
		if(!wm.activeWindow)
			return;
		SwapBuffers(deviceContext);
	}

	void onRawMouse(int x, int y){}

	void setActive(){
		wm.activeWindow = this;
	}

	override void setCursor(Mouse.cursor cursor){
		version(Windows){
			HCURSOR hcur = null;
			if(cursor != Mouse.cursor.none)
				hcur = LoadCursorW(null, cast(const(wchar)*)MOUSE_CURSOR_TO_HCUR[cast(int)cursor]);
			this.cursor = cursor;
			SetCursor(hcur);
			SetClassLongW(windowHandle, -12, cast(LONG)cast(LONG_PTR)hcur);
		}
	}

	void setCursorPos(int x, int y){
		lastX = x;
		lastY = y;
		POINT p = {cast(long)x, cast(long)y};
		ClientToScreen(windowHandle, &p);
		SetCursorPos(p.x, p.y);
	}


	void sendMessage(uint message, WPARAM wpar, LPARAM lpar){
		SendMessageA(windowHandle, message, wpar, lpar);
	}

	/+
	void setTop(){
		SetForegroundWindow(windowHandle);
	}
	+/

	void drawInit(){
		//_draw = new GlDraw;
	}

	void initializeHandlers(){
		eventHandlers = [
			/+
			WM_INPUT: {
				PRAWINPUT pRawInput;
				UINT	  bufferSize;
				HANDLE	hHeap;
				GetRawInputData((HRAWINPUT)lParam, RID_INPUT, NULL, 
				&bufferSize, sizeof(RAWINPUTHEADER));
				hHeap	 = GetProcessHeap();
				pRawInput = (PRAWINPUT)HeapAlloc(hHeap, 0, bufferSize);
				if(!pRawInput)
					return 0;
				GetRawInputData((HRAWINPUT)lParam, RID_INPUT, 
				pRawInput, &bufferSize, sizeof(RAWINPUTHEADER));
				ParseRawInput(pRawInput);
				HeapFree(hHeap, 0, pRawInput);
			},
			+/
			WM_INPUT: (e){
				RAWINPUT input;
				UINT bufferSize = RAWINPUT.sizeof;
				GetRawInputData(cast(HRAWINPUT)e.lpar, RID_INPUT, &input, &bufferSize, RAWINPUTHEADER.sizeof);
				//import ws.io; writeln(cast(byte[RAWINPUT.sizeof])input);
				/+
				if(input.header.dwType == RIM_TYPEMOUSE){
					onRawMouse(input.mouse.lLastX, input.mouse.lLastY);
				}
				+/
			},
			//WM_PAINT: (e){},
			WM_SHOWWINDOW: (e){ onShow; },
			WM_CLOSE: (e){ hide; },
			WM_SIZE: (e){
				resize([LOWORD(e.lpar),HIWORD(e.lpar)]);
			},
			WM_KEYDOWN: (e){
				Keyboard.key c = cast(Keyboard.key)toLower(cast(char)e.wpar);
				Keyboard.set(c, true);
				onKeyboard(c, true);
			},
			WM_KEYUP: (e){
				auto c = cast(Keyboard.key)toLower(cast(char)e.wpar);
				Keyboard.set(c, false);
				onKeyboard(c, false);
			},
			WM_CHAR: (e){
				onKeyboard(cast(dchar)e.wpar);
			},
			WM_ACTIVATE: (e){
				onKeyboardFocus(LOWORD(e.wpar) > 0 ? true : false);
			},
			WM_SETCURSOR: (e){
				SetCursor(MOUSE_CURSOR_TO_HCUR[cast(int)cursor]);
			},
			WM_MOUSEMOVE: (e){
				int x = GET_X_LPARAM(e.lpar);
				int y = GET_Y_LPARAM(e.lpar);
				if(!hasMouse){
					TRACKMOUSEEVENT tme = {
						TRACKMOUSEEVENT.sizeof, 2, windowHandle, 0xFFFFFFFF
					};
					TrackMouseEvent(&tme);
					onMouseFocus(true);
					lastX = x;
					lastY = y;
					hasMouse = true;
				}
				onMouseMove(x, size.y-y);
				onRawMouse(x-lastX, y-lastY);
				lastX = x;
				lastY = y;
			},
			WM_MOUSELEAVE: (e){
				hasMouse = false;
				onMouseFocus(false);
			},
			WM_LBUTTONDOWN: (e){
				onMouseButton(Mouse.buttonLeft, true, LOWORD(e.lpar), size.y-HIWORD(e.lpar));
			},
			WM_LBUTTONUP: (e){
				onMouseButton(Mouse.buttonLeft, false, LOWORD(e.lpar), size.y-HIWORD(e.lpar));
			},
			WM_MBUTTONDOWN: (e){
				onMouseButton(Mouse.buttonMiddle, true, LOWORD(e.lpar), size.y-HIWORD(e.lpar));
			},
			WM_MBUTTONUP: (e){
				onMouseButton(Mouse.buttonMiddle, false, LOWORD(e.lpar), size.y-HIWORD(e.lpar));
			},
			WM_RBUTTONDOWN: (e){
				onMouseButton(Mouse.buttonRight, true, LOWORD(e.lpar), size.y-HIWORD(e.lpar));
			},
			WM_RBUTTONUP: (e){
				onMouseButton(Mouse.buttonRight, false, LOWORD(e.lpar), size.y-HIWORD(e.lpar));
			},
			WM_MOUSEWHEEL: (e){
				onMouseButton(
						GET_WHEEL_DELTA_WPARAM(e.wpar) > 120 ? Mouse.wheelDown : Mouse.wheelUp,
						true, LOWORD(e.lpar), size.y-HIWORD(e.lpar)
				);
			}
		];
	}

	void addEvent(Event e){
		eventQueue ~= e;
	}

	void processEvents(){
		foreach(e; eventQueue)
			if(e.msg in eventHandlers)
				eventHandlers[e.msg](e);
		eventQueue.clear;
	}

}


string getLastError(){
	DWORD errcode = GetLastError();
	if(!errcode)
		return "No error";
	LPCSTR msgBuf;
	DWORD i = FormatMessageA(
		cast(uint)(
		FORMAT_MESSAGE_ALLOCATE_BUFFER |
		FORMAT_MESSAGE_FROM_SYSTEM |
		FORMAT_MESSAGE_IGNORE_INSERTS),
		null,
		errcode,
		cast(uint)MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		cast(LPSTR)&msgBuf,
		0,
		null
	);
	string text = to!string(msgBuf);
	LocalFree(cast(HLOCAL)msgBuf);
	return text;
}
