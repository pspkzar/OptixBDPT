#include <optix_world.h>
#include "sphere_light.h"

using namespace optix;

rtDeclareVariable(optix::Ray, current_ray, rtCurrentRay, );

RT_PROGRAM void sphere_light_bounding_box(int primIdx, float result[6]){
	Aabb *bb = (Aabb*) result;
	float3 center = make_float3(lights[primIdx].pos);
	float3 rad = make_float3(lights[primIdx].pos.w);
	float3 min = center-rad;
	float3 max = center+rad;

	bb->m_min=min;
	bb->m_max=max;
}

RT_PROGRAM void sphere_light_intersect(int primIdx){
	float3 center = make_float3(lights[primIdx].pos);
	float radius = lights[primIdx].pos.w;

	float3 o = current_ray.origin - center;
	float b = dot(o, current_ray.direction);
	float c = dot(o, o) - radius * radius;
	float disc = b * b - c;
	if(disc>0.f){
		float sdisc = sqrtf(disc);
		float root1 = (-b -sdisc);

		if(rtPotentialIntersection(root1)){
			//TODO define attributes
			light = lights[primIdx];
			if(rtReportIntersection(0))
				return;
		}
		float root2 = (-b + sdisc);
		if(rtPotentialIntersection(root2)){
			light = lights[primIdx];
			rtReportIntersection(0);
		}
	}
}
