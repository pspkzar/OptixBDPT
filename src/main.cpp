#include <optix_world.h>
#include <optixu/optixpp_namespace.h>
#include "commonStructs.h"
#include "OptixContext.h"

using namespace optix;
using namespace std;

int main(int argc, char **argv){
	OptixContext c("crytek-sponza/sponza.obj");
	c.setBoundingBoxProgram("mesh.ptx", "boundingBoxMesh");
	c.setIntersectionProgram("mesh.ptx", "intersectMesh");

	c.setRayTypeCount(RAY_TYPE_COUNT);

	c.setClosestHitProgram(PathRay, "path.ptx", "glossy_shading");
	c.setAnyHitProgram(PathRay, "path.ptx", "path_ignore_alpha");

	Context oc = c.getContext();

	Program path_miss = oc->createProgramFromPTXFile("path.ptx", "path_miss");
	oc->setMissProgram(PathRay, path_miss);

	Program camera = oc->createProgramFromPTXFile("path.ptx", "camera");
	Program exception = oc->createProgramFromPTXFile("path.ptx", "exception");
	oc->setEntryPointCount(1);
	oc->setRayGenerationProgram(0, camera);
	oc->setExceptionProgram(0, exception);




	oc->setStackSize(5000);
	oc->setPrintEnabled(true);

	return 0;
}
