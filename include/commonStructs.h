#ifndef COMMONSTRUCTS_H_
#define COMMONSTRUCTS_H_

#include <optix_world.h>

enum RayTypes{
	PathRay,
	ShadowRay,
	RAY_TYPE_COUNT
};

struct SphereLight{
	optix::float4 pos;
	optix::float4 color;
};


#endif /* COMMONSTRUCTS_H_ */
