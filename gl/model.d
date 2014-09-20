
module ws.gl.model;

import file = std.file, std.parallelism;

import
	ws.exception,
	ws.thread.loader,
	ws.gl.gl,
	ws.gl.batch,
	ws.gl.texture,
	ws.gl.material,
	ws.file.obj,
	ws.io,
	ws.log,
	ws.string,
	ws.math.vector;


__gshared:


class Model: Loadable {

	string path;
	BatchMaterial[] data;

	Loader mainFinisher;

	this(string p, Loader glFinisher, Loader mainFinisher){
		assert(glFinisher);
		assert(mainFinisher);
		path = p;
		glFinisher.run(&finish);
		this.mainFinisher = mainFinisher;
	}

	bool isValid(){
		return valid;
	}


	class BatchMaterial {

		Batch batch;
		Material mat;

		private:
			
			OBJ.Material material;

			void finishBatch(){
				assert(!batch);
				assert(material);
				scope(exit)
					material = null;
				batch = new Batch;
				batch.begin(material.vertcount);
				foreach(polygon; material.polygons){
					foreach(vertex; polygon.vertices){
						float[2] uvw = vertex.uvw.data[0..2];
						batch.addPoint(vertex.pos, vertex.normal, uvw);
					}
				}
				batch.finish();
			}

			void finishMaterial(OBJ mdl){
				assert(!mat);
				try {
					string[string] partsVertex = ["singlelight": "forwardSpecular"];
					string[string] partsFragment = ["singlelight": "getSpecular"];
					int[string] attributes = [
						"vertex": gl.attributeVertex,
						"normal": gl.attributeNormal,
						"texture": gl.attributeTexture
					];
					mat = new Material(
						path ~ ':' ~ material.name, partsVertex, partsFragment, attributes
					);
					float[3] col = [1,1,1];
					mat.addUniform("diffuseColor", col);
					foreach(mtllib; mdl.mtllibs){
						foreach(mtl; mtllib.mtls){
							if(mtl.name == material.name){
								if(mtl.mapDiffuse.length){
									mat.linkVertex("texture", "getTexCoords");
									mat.linkFragment("texture", "getTexColor");
									mat.addTexture("Texture", mtl.mapDiffuse);
								}
								/*if(mtl.mapBump.length){
								partsVertex["bump"] = "forwardBump";
								partsFragment["bump"] = "getBump";
								b.mat.addTexture("Bump", mtl.mapBump);
								}*/
								break;
							}
						}
					}
					mainFinisher.run(&mat.finish);
				}catch(Exception e){
					Log.warning(e.toString());
					mat = null;
				}
			}

	};

	private:

		void finish(){
			loadState = Loading;
			auto mdl = new OBJ("models/" ~ path);
			foreach(object; mdl.objects){
				foreach(material; object.materials.values){
					auto b = new BatchMaterial;
					data ~= b;
					b.material = material;
					mainFinisher.run(&b.finishBatch);
					b.finishMaterial(mdl);
				}
			}
			loadState = Loaded;
		}

		bool valid = false;

}



