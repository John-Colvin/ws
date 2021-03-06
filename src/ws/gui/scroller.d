module ws.gui.scroller;

import
	std.math,
	std.algorithm,
	std.conv,
	ws.time,
	ws.gui.base;


class Scroller: Base {
	
	double scroll = 0;
	double scrollSpeed = 0;
	double frameTime;
	double frameLast;
	
	override void resize(int[2] size){
		super.resize(size);
		update;
	}

	void update(){
		if(!children.length)
			return;
		foreach(c; children){
			c.move([pos.x, pos.y+size.h-c.size.h+scroll.to!int]);
			c.resize([size.w, c.size.h]);
		}
		onMouseMove(cursorPos.x, cursorPos.y);
		
	}

	override void resizeRequest(Base child, int[2] size){
		child.resize(size);
		scroll = scroll.min(size.h - this.size.h).max(0);
		update;
	}

	override void onMouseButton(Mouse.button button, bool pressed, int x, int y){
		if(!children.length)
			return;
		auto maxOffset = (children[0].size.h - size.h).max(0);
		if(button == Mouse.wheelDown && scroll < maxOffset){
			if(pressed){
				scrollSpeed += 25+scrollSpeed.abs;
				return;
			}
		}else if(button == Mouse.wheelUp && scroll > 0){
			if(pressed){
				scrollSpeed -= 25+scrollSpeed.abs;
				return;
			}
		}else
			super.onMouseButton(button, pressed, x, y);
	}

	override void onDraw(){
		if(hidden)
			return;
		frameTime = now-frameLast;
		frameLast = now;
		if(scrollSpeed){
			scroll = (scroll + scrollSpeed*frameTime*30).min(children[0].size.h - size.h).max(0);
			scrollSpeed = scrollSpeed.eerp(0, frameTime*15, frameTime*7.5, frameTime/50);
			update;
		}
		draw.clip(pos, size);
		super.onDraw();
		draw.noclip;
	}

}


double eerp(double current, double target, double a, double b, double c){
	auto dir = current < target ? 1 : -1;
	auto diff = (current-target).abs;
	return current + (dir*(c*diff^^2 + b*diff + a)).min(diff).max(-diff);
}

