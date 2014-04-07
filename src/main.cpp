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

	c.setClosestHitProgram(PathRay, "path.ptx", "closest_hit");
	c.setAnyHitProgram(PathRay, "path.ptx", "any_hit");
	c.setMissProgram(PathRay, "path.ptx", "miss");
	Context oc = c.getContext();
	oc->setEntryPointCount(1);
	Program camera = oc->createProgramFromPTXFile("path.ptx", "camera");
	oc->setRayGenerationProgram(0, camera);
	Buffer output = oc->createBuffer(RT_BUFFER_OUTPUT, RT_FORMAT_FLOAT4, 200, 200);
	oc["output"]->set(output);

	oc->validate();
	oc->launch(0, 200, 200);
	return 0;
}
