/*
 * OptixContext.h
 *
 *  Created on: 5 de Abr de 2014
 *      Author: cesar
 */

#ifndef OPTIXCONTEXT_H_
#define OPTIXCONTEXT_H_

#include <iostream>
#include <map>

#include <assimp/scene.h>

#include <optix_world.h>
#include <optixu/optixpp.h>

class OptixContext {
public:
	OptixContext(std::string scene_name);
	virtual ~OptixContext();

	optix::TextureSampler loadTextureRGBA(std::string &file);
	optix::TextureSampler loadTextureLum(std::string &file);

	optix::Acceleration newSBVH();
	optix::Acceleration newBVH();

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
