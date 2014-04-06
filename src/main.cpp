#include <optix_world.h>
#include <optixu/optixpp_namespace.h>
#include "commonStructs.h"
#include "OptixContext.h"

int main(int argc, char **argv){
	OptixContext c("crytek-sponza/sponza.obj");
	c.setBoundingBoxProgram("mesh.ptx", "boundingBoxMesh");
	c.setIntersectionProgram("mesh.ptx", "intersectMesh");

	return 0;
}
