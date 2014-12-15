#ifndef OPTIXCONTEXT_H_
#define OPTIXCONTEXT_H_

#include <iostream>
#include <map>

#include <assimp/scene.h>

#include <optix_world.h>
#include <optixu/optixpp_namespace.h>

class OptixContext {
public:
	OptixContext(std::string scene_name);
	virtual ~OptixContext();

	optix::TextureSampler loadTextureRGBA(std::string &file);
	optix::TextureSampler loadTextureLum(std::string &file);

	optix::Acceleration newAccel();

	void setRayTypeCount(int nray_types);
	void setClosestHitProgram(int ray_type, std::string file, std::string program);
	void setAnyHitProgram(int ray_type, std::string file, std::string program);

	void setMaterialClosestHitProgram(std::string material, int ray_type, std::string file, std::string program);
	void setMaterialAnyHitProgram(std::string material, int ray_type, std::string file, std::string program);

	void setBoundingBoxProgram(std::string file, std::string program);
	void setIntersectionProgram(std::string file, std::string program);

	optix::Context getContext() {return _context;}
	optix::GeometryGroup getMeshes() {return _meshes;}

private:
	void loadMaterials();
	void loadMeshes();

	optix::TextureSampler emptyTextureRGBA();
	optix::TextureSampler emptyTextureLum();

	std::string _working_directory;
	const aiScene *_scene;
	optix::Context _context;
	std::map<std::string, optix::Material> _materials;
	optix::GeometryGroup _meshes;

};

#endif /* OPTIXCONTEXT_H_ */
