#ifndef COMMONSTRUCTS_H_
#define COMMONSTRUCTS_H_

#include <optix_world.h>
#include <optixu/optixpp_namespace.h>
#include <vector_types.h>
#include "sphere_light_common.h"

#define LIGHT_PATH_LENGTH 3

enum RayTypes{
	PathRay,
	ShadowRay,
	LightPathRay,
	RAY_TYPE_COUNT
};

struct LightPathResult{
	optix::float3 position;
	optix::float3 normal;

	optix::float3 In;
	optix::float4 radiance;

	optix::float4 Kd;
	optix::float4 Ks;

	float Ni;
	float Ns;

	bool missed;
};

#endif /* COMMONSTRUCTS_H_ */
