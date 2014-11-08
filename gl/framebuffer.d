module ws.gl.framebuffer;

import
	std.string,
	ws.gl.gl;


string error(GLuint i){
	string[GLuint] ERRORS = [
		GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT: "invalid attachment(s)",
	//	GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS: "invalid dimensions",
		GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT: "no attachments",
		GL_FRAMEBUFFER_UNSUPPORTED: "this framebuffer configuration is not supported"
	];
	return ERRORS[i];
}



class FrameBuffer {

	private {
		GLuint fbo;
		GLuint depth;
		GLuint[] textures;
		uint width, height;
	}

	this(int w, int h, int count, GLuint format=GL_RGBA32F, GLuint type=GL_FLOAT, GLuint colors=GL_RGB){
		width = w;
		height = h;
		glGenFramebuffers(1, &fbo); 
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		textures = new GLuint[count];
		glGenTextures(cast(int)textures.length, textures.ptr);
		for(uint i = 0; i < textures.length; i++){
			glBindTexture(GL_TEXTURE_2D, textures[i]);
    		glTexImage2D(GL_TEXTURE_2D, 0, format, w, h, 0, colors, type, null);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	        glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, textures[i], 0);
		}
		glGenTextures(1, &depth);
		glBindTexture(GL_TEXTURE_2D, depth);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH32F_STENCIL8, w, h, 0, GL_DEPTH_STENCIL, GL_FLOAT_32_UNSIGNED_INT_24_8_REV, null);
		glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, depth, 0);
		
		GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		if(status != GL_FRAMEBUFFER_COMPLETE)
			throw new Exception("FB error: %s".format(error(status)));

		glBindFramebuffer(GL_FRAMEBUFFER, 0);
	}

	void destroy(){
		glDeleteFramebuffers(1, &fbo);
		glDeleteTextures(cast(int)textures.length, textures.ptr);
		glDeleteRenderbuffers(1, &depth);
	}

	void draw(GLuint[] targets){
		glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo);
		GLuint[] drawBuffers;
		foreach(i, n; targets)
			drawBuffers ~= GL_COLOR_ATTACHMENT0+n;
		glDrawBuffers(cast(int)drawBuffers.length, drawBuffers.ptr);
	}

	void read(GLuint target){
		glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
		glReadBuffer(GL_COLOR_ATTACHMENT0+target);
	}

	/+++
		Bind textures for reading
		tex: [shader offset: framebuffer index, ...]
	+/
	void read(uint[uint] tex){
		foreach(i, n; tex){
			glActiveTexture(GL_TEXTURE0+i);
			glBindTexture(GL_TEXTURE_2D, textures[n]);
		}
	}

	void blit(int which, int x, int y, int w){
		float aspect = width/cast(float)height;
		int h = cast(int)(w/aspect);
		read(which);
		glBlitFramebuffer(0,0,width,height,x,y,x+w,y+h,GL_COLOR_BUFFER_BIT,GL_LINEAR);
	}

}
