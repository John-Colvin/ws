module ws.x.draw;

version(Posix):


import
	std.string,
	std.algorithm,
	std.math,
	std.conv,
	x11.X,
	x11.Xlib,
	x11.extensions.render,
	x11.extensions.Xrender,
	ws.draw,
	ws.wm,
	ws.bindings.xft,
	ws.gui.point,
	ws.x.font;


class Color {

	ulong pix;
	XftColor rgb;
	long[4] rgba;

	this(Display* dpy, int screen, long[4] values){
		Colormap cmap = DefaultColormap(dpy, screen);
		Visual* vis = DefaultVisual(dpy, screen);
		rgba = values;
		auto name = "#%02x%02x%02x".format(values[0], values[1], values[2]);
		if(!XftColorAllocName(dpy, vis, cmap, name.toStringz, &rgb))
			throw new Exception("Cannot allocate color " ~ name);
		pix = rgb.pixel;
	}

}

class Cur {
	Cursor cursor;
	this(Display* dpy, int shape){
		cursor = XCreateFontCursor(dpy, shape);
	}
	void destroy(Display* dpy){
		XFreeCursor(dpy, cursor);
	}
}

class Icon {
	Picture picture;
	int[2] size;
	void destroy(Display* dpy){
		XRenderFreePicture(dpy, picture);
	}
}

class XDraw: DrawEmpty {

	int[2] size;
	Display* dpy;
	int screen;
	x11.X.Window window;
	Visual* visual;
	Drawable drawable;
	XftDraw* xft;
	GC gc;

	Color color;
	Color[long[4]] colors;

	ws.x.font.Font font;
	ws.x.font.Font[string] fonts;

	XRectangle[] clipStack;

	Picture frontBuffer;

	this(ws.wm.Window window){
		this(wm.displayHandle, window.windowHandle);
	}

	this(Display* dpy, x11.X.Window window){
		XWindowAttributes wa;
		XGetWindowAttributes(dpy, window, &wa);
		this.dpy = dpy;
		screen = DefaultScreen(dpy);
		this.window = window;
		this.size = [wa.width, wa.height];
		drawable = XCreatePixmap(dpy, window, size.w, size.h, wa.depth);
		gc = XCreateGC(dpy, window, 0, null);
		XSetLineAttributes(dpy, gc, 1, LineSolid, CapButt, JoinMiter);
		xft = XftDrawCreate(dpy, drawable, wa.visual, wa.colormap);
		visual = wa.visual;
		auto format = XRenderFindVisualFormat(dpy, wa.visual);
		XRenderPictureAttributes pa;
		pa.subwindow_mode = IncludeInferiors;
		frontBuffer = XRenderCreatePicture(dpy, drawable, format, CPSubwindowMode, &pa);
	}

	this(x11.X.Window root, Drawable drawable, Picture frontBuffer){
		dpy = wm.displayHandle;
		screen = DefaultScreen(dpy);
		XWindowAttributes wa;
		XGetWindowAttributes(dpy, root, &wa);
		this.drawable = drawable;
		this.frontBuffer = frontBuffer;
		xft = XftDrawCreate(dpy, drawable, wa.visual, wa.colormap);
	}

	~this(){
		if(drawable)
			XFreePixmap(dpy, drawable);
		if(frontBuffer)
			XRenderFreePicture(dpy, frontBuffer);
	}

	override int width(string text){
		return font.width(text);
	}

	override void resize(int[2] size){
		if(this.size == size)
			return;
		this.size = size;
		if(drawable)
			XFreePixmap(dpy, drawable);
		drawable = XCreatePixmap(dpy, window, size.w, size.h, DefaultDepth(dpy, screen));
		auto format = XRenderFindVisualFormat(dpy, visual);
		XRenderPictureAttributes pa;
		pa.subwindow_mode = IncludeInferiors;
		if(frontBuffer)
			XRenderFreePicture(dpy, frontBuffer);
		frontBuffer = XRenderCreatePicture(dpy, drawable, format, CPSubwindowMode, &pa);
		XftDrawChange(xft, drawable);
	}

	override void destroy(){
		foreach(font; fonts)
			font.destroy;
		XFreePixmap(dpy, drawable);
		XRenderFreePicture(dpy, frontBuffer);
		drawable = None;
		frontBuffer = None;
		XftDrawDestroy(xft);
		XFreeGC(dpy, gc);
	}

	override void setFont(string font, int size){
		font ~= ":size=%d".format(size);
		if(font !in fonts)
			fonts[font] = new ws.x.font.Font(dpy, screen, font);
		this.font = fonts[font];
	}

	override int fontHeight(){
		return font.h;
	}

	override void setColor(float[3] color){
		setColor([color[0], color[1], color[2], 1]);
	}

	override void setColor(float[4] color){
		long[4] values = [
			(color[0]*255).lround.max(0).min(255),
			(color[1]*255).lround.max(0).min(255),
			(color[2]*255).lround.max(0).min(255),
			(color[3]*255).lround.max(0).min(255)
		];
		if(values !in colors)
			colors[values] = new Color(dpy, screen, values);
		this.color = colors[values];
	}

	override void clip(int[2] pos, int[2] size){
		pos[1] = this.size[1] - pos[1] - size[1];
		if(clipStack.length){
			auto rect = clipStack[$-1];
			auto maxx = rect.x + rect.width;
			auto maxy = rect.y + rect.height;
			pos = [
					pos.x.max(rect.x).min(maxx),
					pos.y.max(rect.y).min(maxy)
			];
			size = [
					(pos.x+size.w.min(rect.width)).min(maxx)-pos.x,
					(pos.y+size.h.min(rect.height)).min(maxy)-pos.y
			];
		}
		auto rect = XRectangle(cast(short)pos[0], cast(short)pos[1], cast(short)size[0], cast(short)size[1]);
		XftDrawSetClipRectangles(xft, 0, 0, &rect, 1);
		if(gc)
			XSetClipRectangles(dpy, gc, 0, 0, &rect, 1, Unsorted);
		clipStack ~= rect;
	}

	override void noclip(){
		clipStack = clipStack[0..$-1];
		if(clipStack.length){
			auto rect = clipStack[$-1];
			XftDrawSetClipRectangles(xft, 0, 0, &rect, 1);
			if(gc)
				XSetClipRectangles(dpy, gc, 0, 0, &rect, 1, Unsorted);
		}else{
			if(gc)
				XSetClipMask(dpy, gc, None);
			XftDrawSetClip(xft, null);
		}
	}

	override void rect(int[2] pos, int[2] size){
		auto a = this.color.rgba[3]/255.0;
		XRenderColor color = {
			(this.color.rgba[0]*255*a).to!ushort,
			(this.color.rgba[1]*255*a).to!ushort,
			(this.color.rgba[2]*255*a).to!ushort,
			(this.color.rgba[3]*255).to!ushort
		};
		XRenderFillRectangle(dpy, PictOpOver, frontBuffer, &color, pos.x, this.size.h-size.h-pos.y, size.w, size.h);
	}

	override void rectOutline(int[2] pos, int[2] size){
		XSetForeground(dpy, gc, color.pix);
		XDrawRectangle(dpy, drawable, gc, pos.x, this.size.h-pos.y-size.h, size.w, size.h);
	}

	override void line(int[2] start, int[2] end){
		XSetForeground(dpy, gc, color.pix);
		XDrawLine(dpy, drawable, gc, start.x, start.y, end.x, end.y);
	}

	override int text(int[2] pos, string text, double offset=-0.2){
		if(text.length){
			auto width = width(text);
			auto fontHeight = font.h;
			auto offsetRight = max(0.0,-offset)*fontHeight;
			auto offsetLeft = max(0.0,offset-1)*fontHeight;
			auto x = pos.x - min(1,max(0,offset))*width + offsetRight - offsetLeft;
			auto y = this.size.h - pos.y - 2;
			XftDrawStringUtf8(xft, &color.rgb, font.xfont, cast(int)x.lround, cast(int)y.lround, text.toStringz, cast(int)text.length);
			return this.width(text);
		}
		return 0;
	}
	
	override int text(int[2] pos, int h, string text, double offset=-0.2){
		pos.y += ((h-font.h)/2.0).lround;
		return this.text(pos, text, offset);
	}

	Icon icon(ubyte[] data, int[2] size){
		assert(data.length == size.w*size.h*4, "%s != %s*%s*4".format(data.length, size.w, size.h));
		auto res = new Icon;

		auto img = XCreateImage(
				dpy,
				null,
				32,
				ZPixmap,
				0,
				cast(char*)data.ptr,
				cast(uint)size.w,
				cast(uint)size.h,
				32,
				0
		);

		auto pixmap = XCreatePixmap(dpy, drawable, size.w, size.h, 32);

     	XRenderPictureAttributes attributes;
		auto gc = XCreateGC(dpy, pixmap, 0, null);
	    XPutImage(dpy, pixmap, gc, img, 0, 0, 0, 0, size.w, size.h);
     	auto pictformat = XRenderFindStandardFormat(dpy, PictStandardARGB32);
     	res.picture = XRenderCreatePicture(dpy, pixmap, pictformat, 0, &attributes);
		XRenderSetPictureFilter(dpy, res.picture, "best", null, 0);
		XFreePixmap(dpy, pixmap);

		res.size = size;
		return res;
		/+
		res.pixmap = XCreatePixmap(wm.displayHandle, window, DisplayWidth(wm.displayHandle, 0), DisplayHeight(wm.displayHandle, 0), DefaultDepth(wm.displayHandle, 0));
		res.picture = XRenderCreatePicture(wm.displayHandle, pixmap, format, 0, null);
		XFreePixmap(wm.displayHandle, res.pixmap);
		+/
		
	}

	void icon(Icon icon, int x, int y, double scale, Picture alpha=None){
		XTransform xform = {[
			[XDoubleToFixed( 1 ), XDoubleToFixed( 0 ), XDoubleToFixed( 0 )],
			[XDoubleToFixed( 0 ), XDoubleToFixed( 1 ), XDoubleToFixed( 0 )],
			[XDoubleToFixed( 0 ), XDoubleToFixed( 0 ), XDoubleToFixed( scale )]
		]};
		XRenderSetPictureTransform(dpy, icon.picture, &xform);
		XRenderComposite(dpy, PictOpOver, icon.picture, alpha, frontBuffer, 0, 0, 0, 0, x, y, (icon.size.w*scale).to!int, (icon.size.h*scale).to!int);
	}

	override void finishFrame(){
		XCopyArea(dpy, drawable, window, gc, 0, 0, size.w, size.h, 0, 0);
		XSync(dpy, False);
	}

}

