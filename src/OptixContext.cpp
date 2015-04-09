#include "OptixContext.h"
#include <assimp/cimport.h>
#include <assimp/postprocess.h>
#include <IL/il.h>
#include <IL/ilu.h>

#define ANISOTROPY 0.f

using namespace std;
using namespace optix;

OptixContext::OptixContext(string scene_name) {
	_scene = aiImportFile(scene_name.c_str(), aiProcessPreset_TargetRealtime_MaxQuality | aiProcess_PreTransformVertices );

	int slash_i=scene_name.find_last_of("\\/");
	if(slash_i==scene_name.npos){
		_working_directory="";
	}
	else{
		_working_directory=scene_name.substr(0, slash_i+1);
	}
	ilInit();
	_context = Context::create();
	loadMaterials();
	loadMeshes();

	aiReleaseImport(_scene);
}

OptixContext::~OptixContext() {
	_context->destroy();
}

TextureSampler OptixContext::loadTextureRGBA(string &file) {
	ILuint image = ilGenImage();
	ilBindImage(image);
	ilEnable(IL_ORIGIN_SET);
	ilOriginFunc(IL_ORIGIN_LOWER_LEFT);

	TextureSampler tex = _context->createTextureSampler();
	tex->setArraySize(1);
	tex->setMipLevelCount(1);
	tex->setWrapMode(0, RT_WRAP_REPEAT);
	tex->setWrapMode(1, RT_WRAP_REPEAT);
	tex->setReadMode(RT_TEXTURE_READ_NORMALIZED_FLOAT);
	tex->setIndexingMode(RT_TEXTURE_INDEX_NORMALIZED_COORDINATES);
	tex->setFilteringModes(RT_FILTER_LINEAR, RT_FILTER_LINEAR, RT_FILTER_NONE);
	tex->setMaxAnisotropy(ANISOTROPY);

	ILboolean success = ilLoadImage(file.c_str());
	if(success){
		ilConvertImage(IL_RGBA, IL_UNSIGNED_BYTE);
		int w=ilGetInteger(IL_IMAGE_WIDTH);
		int h=ilGetInteger(IL_IMAGE_HEIGHT);
		Buffer tex_buffer = _context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_UNSIGNED_BYTE4, w, h);

		void *data = ilGetData();
		int size = ilGetInteger(IL_IMAGE_SIZE_OF_DATA);

		void* tex_data = tex_buffer->map();

		memcpy(tex_data, data, size);

		tex_buffer->unmap();
		tex_buffer->validate();

		tex->setBuffer(0, 0, tex_buffer);
	}
	tex->validate();

	return tex;
}



TextureSampler OptixContext::loadTextureLum(string &file) {
	ILuint image = ilGenImage();
	ilBindImage(image);
	ilEnable(IL_ORIGIN_SET);
	ilOriginFunc(IL_ORIGIN_LOWER_LEFT);

	TextureSampler tex = _context->createTextureSampler();
	tex->setArraySize(1);
	tex->setMipLevelCount(1);
	tex->setWrapMode(0, RT_WRAP_REPEAT);
	tex->setWrapMode(1, RT_WRAP_REPEAT);
	tex->setReadMode(RT_TEXTURE_READ_NORMALIZED_FLOAT);
	tex->setIndexingMode(RT_TEXTURE_INDEX_NORMALIZED_COORDINATES);
	tex->setFilteringModes(RT_FILTER_LINEAR, RT_FILTER_LINEAR, RT_FILTER_NONE);
	tex->setMaxAnisotropy(ANISOTROPY);

	ILboolean success = ilLoadImage(file.c_str());
	if(success){
		ilConvertImage(IL_LUMINANCE, IL_UNSIGNED_BYTE);
		int w=ilGetInteger(IL_IMAGE_WIDTH);
		int h=ilGetInteger(IL_IMAGE_HEIGHT);
		Buffer tex_buffer = _context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_UNSIGNED_BYTE, w, h);

		void *data = ilGetData();
		int size = ilGetInteger(IL_IMAGE_SIZE_OF_DATA);

		void* tex_data = tex_buffer->map();

		memcpy(tex_data, data, size);

		tex_buffer->unmap();
		tex_buffer->validate();

		tex->setBuffer(0, 0, tex_buffer);
	}
	tex->validate();
	return tex;
}

TextureSampler OptixContext::emptyTextureRGBA() {

	TextureSampler tex = _context->createTextureSampler();
	tex->setArraySize(1);
	tex->setMipLevelCount(1);
	tex->setWrapMode(0, RT_WRAP_REPEAT);
	tex->setWrapMode(1, RT_WRAP_REPEAT);
	tex->setReadMode(RT_TEXTURE_READ_NORMALIZED_FLOAT);
	tex->setIndexingMode(RT_TEXTURE_INDEX_NORMALIZED_COORDINATES);
	tex->setFilteringModes(RT_FILTER_LINEAR, RT_FILTER_LINEAR, RT_FILTER_NONE);
	tex->setMaxAnisotropy(0.f);

	Buffer white = _context->createBuffer(RT_BUFFER_INPUT,RT_FORMAT_UNSIGNED_BYTE4,1,1);

	unsigned char * bytes = static_cast<unsigned char *>(white->map());
	bytes[0]=255;
	bytes[1]=255;
	bytes[2]=255;
	bytes[3]=255;
	white->unmap();
	white->validate();
	tex->setBuffer(0,0,white);
	tex->validate();

	return tex;
}


TextureSampler OptixContext::emptyTextureLum() {

	TextureSampler tex = _context->createTextureSampler();
	tex->setArraySize(1);
	tex->setMipLevelCount(1);
	tex->setWrapMode(0, RT_WRAP_REPEAT);
	tex->setWrapMode(1, RT_WRAP_REPEAT);
	tex->setReadMode(RT_TEXTURE_READ_NORMALIZED_FLOAT);
	tex->setIndexingMode(RT_TEXTURE_INDEX_NORMALIZED_COORDINATES);
	tex->setFilteringModes(RT_FILTER_LINEAR, RT_FILTER_LINEAR, RT_FILTER_NONE);
	tex->setMaxAnisotropy(0.f);

	Buffer white = _context->createBuffer(RT_BUFFER_INPUT,RT_FORMAT_UNSIGNED_BYTE,1,1);

	unsigned char * bytes = static_cast<unsigned char *>(white->map());
	bytes[0]=255;
	white->unmap();
	white->validate();
	tex->setBuffer(0,0,white);
	tex->validate();

	return tex;
}


void OptixContext::loadMaterials() {
	int nmat=_scene->mNumMaterials;

	TextureSampler whiteRGBA = emptyTextureRGBA();
	TextureSampler noBumpTex = emptyTextureLum();

	for(int i=0; i<nmat; i++){
		aiMaterial *mat=_scene->mMaterials[i];
		aiString matName;
		aiGetMaterialString(mat, AI_MATKEY_NAME, &matName);
		Material optix_mat = _context->createMaterial();

		aiColor4D diffuse;
		aiGetMaterialColor(mat, AI_MATKEY_COLOR_DIFFUSE, &diffuse);
		optix_mat["Kd"]->setFloat(diffuse.r, diffuse.b, diffuse.g, diffuse.a);

		aiColor4D specular;
		aiGetMaterialColor(mat, AI_MATKEY_COLOR_SPECULAR, &specular);
		optix_mat["Ks"]->setFloat(specular.r, specular.b, specular.g, specular.a);

		float shininess;
		aiGetMaterialFloat(mat, AI_MATKEY_SHININESS, &shininess);
		optix_mat["Ns"]->setFloat(shininess);

		float ior;
		aiGetMaterialFloat(mat, AI_MATKEY_REFRACTI, &ior);
		optix_mat["Ni"]->setFloat(ior);


		aiString diffTexPath;
		if(AI_SUCCESS==mat->GetTexture(aiTextureType_DIFFUSE, 0, &diffTexPath)){
			string tex_path=_working_directory+string(diffTexPath.data);
			TextureSampler diffTex = loadTextureRGBA(tex_path);
			optix_mat["map_Kd"]->setTextureSampler(diffTex);
		}
		else{
			optix_mat["map_Kd"]->setTextureSampler(whiteRGBA);
		}


		aiString specTexPath;
		if(AI_SUCCESS==mat->GetTexture(aiTextureType_SPECULAR, 0, &specTexPath)){
			string tex_path=_working_directory+string(specTexPath.data);
			TextureSampler specTex = loadTextureRGBA(tex_path);
			optix_mat["map_Ks"]->setTextureSampler(specTex);
		}
		else{
			optix_mat["map_Ks"]->setTextureSampler(whiteRGBA);
		}


		aiString bumpTexPath;
		if(AI_SUCCESS==mat->GetTexture(aiTextureType_HEIGHT, 0, &bumpTexPath)){
			string tex_path=_working_directory+string(bumpTexPath.data);
			TextureSampler bumpTex = loadTextureRGBA(tex_path);
			optix_mat["map_bump"]->setTextureSampler(bumpTex);
			optix_mat["has_bump"]->setInt(1);
		}
		else{
			optix_mat["map_bump"]->setTextureSampler(whiteRGBA);
			optix_mat["has_bump"]->setInt(0);
		}

		optix_mat->validate();

		_materials[string(matName.data)]=optix_mat;
	}
}

Acceleration OptixContext::newAccel() {
	return _context->createAcceleration("Trbvh", "Bvh");
}

void OptixContext::loadMeshes() {
	_meshes=_context->createGeometryGroup();

	Acceleration acc = newAccel();
	acc->setProperty("vertex_buffer_name","vertex_buffer");
	acc->setProperty("vertex_buffer_stride","0");
	acc->setProperty("index_buffer_name","index_buffer");
	acc->setProperty("index_buffer_stride","0");

	_meshes->setAcceleration(acc);

	int nmeshes = _scene->mNumMeshes;
	_meshes->setChildCount(nmeshes);

	Buffer noTexCoord = _context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_FLOAT2, 1);
	Buffer noTangents = _context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_FLOAT3, 1);

	for(int i=0; i<nmeshes; i++){

		aiMesh *mesh = _scene->mMeshes[i];
		Geometry optix_mesh = _context->createGeometry();
		optix_mesh->setPrimitiveCount(mesh->mNumFaces);

		//loading indices
		Buffer index_buffer = _context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_INT3, mesh->mNumFaces);
		int3 *tmp_index = static_cast<int3 *>(index_buffer->map());
		for(int n=0; n<mesh->mNumFaces; n++){
			tmp_index[n] = make_int3(mesh->mFaces[n].mIndices[0], mesh->mFaces[n].mIndices[1], mesh->mFaces[n].mIndices[2]);
		}
		index_buffer->unmap();
		index_buffer->validate();

		//loading vertices
		Buffer vertex_buffer = _context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_FLOAT3, mesh->mNumVertices);
		float3 *tmp_vertex = static_cast<float3 *>(vertex_buffer->map());
		for(int n=0; n<mesh->mNumVertices; n++){
			tmp_vertex[n] = make_float3(mesh->mVertices[n].x, mesh->mVertices[n].y, mesh->mVertices[n].z);
		}
		vertex_buffer->unmap();
		vertex_buffer->validate();

		//loading normals
		Buffer normal_buffer = _context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_FLOAT3, mesh->mNumVertices);
		float3 *tmp_normal = static_cast<float3 *>(normal_buffer->map());
		for(int n=0; n<mesh->mNumVertices; n++){
			tmp_normal[n]=make_float3(mesh->mNormals[n].x, mesh->mNormals[n].y, mesh->mNormals[n].z);
		}
		normal_buffer->unmap();
		normal_buffer->validate();

		//loading tex coordinates if available
		Buffer texCoord_buffer;
		if(mesh->HasTextureCoords(0)){
			texCoord_buffer=_context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_FLOAT2, mesh->mNumVertices);
			float2 * tmp_texCoord = static_cast<float2 *>(texCoord_buffer->map());
			for(int n=0; n<mesh->mNumVertices; n++){
				tmp_texCoord[n]=make_float2(mesh->mTextureCoords[0][n].x, mesh->mTextureCoords[0][n].y);
			}
			texCoord_buffer->unmap();
			texCoord_buffer->validate();
		}
		else texCoord_buffer = noTexCoord;

		//loading tangents and bitangenst if available
		Buffer tangent_buffer;
		Buffer bitangent_buffer;
		if(mesh->HasTangentsAndBitangents()){

			tangent_buffer=_context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_FLOAT3, mesh->mNumVertices);
			float3 *tmp_tangent = static_cast<float3 *>(tangent_buffer->map());
			for(int n=0; n<mesh->mNumVertices; n++){
				tmp_tangent[n]=make_float3(mesh->mTangents[n].x, mesh->mTangents[n].y, mesh->mTangents[n].z);
			}
			tangent_buffer->unmap();
			tangent_buffer->validate();

			bitangent_buffer=_context->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_FLOAT3, mesh->mNumVertices);
			float3 *tmp_bitangent = static_cast<float3 *>(bitangent_buffer->map());
			for(int n=0; n<mesh->mNumVertices; n++){
				tmp_bitangent[n]=make_float3(mesh->mBitangents[n].x, mesh->mBitangents[n].y, mesh->mBitangents[n].z);
			}
			bitangent_buffer->unmap();
			bitangent_buffer->validate();
		}
		else{
			tangent_buffer=noTangents;
			bitangent_buffer=noTangents;
		}

		optix_mesh["vertex_buffer"]->set(vertex_buffer);
		optix_mesh["index_buffer"]->set(index_buffer);
		optix_mesh["normal_buffer"]->set(normal_buffer);

		optix_mesh["texCoord_buffer"]->set(texCoord_buffer);

		optix_mesh["tangent_buffer"]->set(tangent_buffer);
		optix_mesh["bitangent_buffer"]->set(bitangent_buffer);

		aiString mat_name;
		aiGetMaterialString(_scene->mMaterials[mesh->mMaterialIndex], AI_MATKEY_NAME, &mat_name);
		string mname(mat_name.data);

		GeometryInstance instance = _context->createGeometryInstance();
		instance->setGeometry(optix_mesh);
		instance->setMaterialCount(1);
		instance->setMaterial(0, _materials[mname]);

		_meshes->setChild(i, instance);
	}

}

void OptixContext::setRayTypeCount(int nray_types) {
	_context->setRayTypeCount(nray_types);
}

void OptixContext::setClosestHitProgram(int ray_type, string file, string program) {
	Program p = _context->createProgramFromPTXFile(file, program);
	p->validate();
	for(map<string, Material>::iterator i=_materials.begin(); i!=_materials.end(); i++){
		i->second->setClosestHitProgram(ray_type, p);
	}
}

void OptixContext::setAnyHitProgram(int ray_type, std::string file, std::string program) {
	Program p = _context->createProgramFromPTXFile(file, program);
	p->validate();
	for(map<string, Material>::iterator i=_materials.begin(); i!=_materials.end(); i++){
		i->second->setAnyHitProgram(ray_type, p);
	}
}


void OptixContext::setMaterialClosestHitProgram(string material, int ray_type, string file, string program) {
	Program p = _context->createProgramFromPTXFile(file, program);
	p->validate();
	Material m = _materials[material];
	m->setClosestHitProgram(ray_type, p);
}

void OptixContext::setMaterialAnyHitProgram(string material, int ray_type, string file, string program) {
	Program p = _context->createProgramFromPTXFile(file, program);
	p->validate();
	Material m = _materials[material];
	m->setAnyHitProgram(ray_type, p);
}

void OptixContext::setBoundingBoxProgram(string file, string program) {
	Program p = _context->createProgramFromPTXFile(file, program);
	p->validate();
	for(int i=0; i<_meshes->getChildCount(); i++){
		_meshes->getChild(i)->getGeometry()->setBoundingBoxProgram(p);
	}
}

void OptixContext::setIntersectionProgram(string file, string program) {
	Program p = _context->createProgramFromPTXFile(file, program);
	p->validate();
	for(int i=0; i<_meshes->getChildCount(); i++){
		_meshes->getChild(i)->getGeometry()->setIntersectionProgram(p);
	}
}


