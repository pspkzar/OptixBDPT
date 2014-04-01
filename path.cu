#include <optix_world.h>
#include "random.h"

rtDeclareVariable(float4, Kd, , );
rtDeclareVariable(float4, Ks, , );
rtDeclareVariable(float, shininess, , );


// Intersection attributes
rtDeclareVariable(float3, pos, attribute pos, );
rtDeclareVariable(float3, geometric_normal, attribute geometric_normal, );
rtDeclareVariable(float3, shading_normal, attribute shading_normal, );
rtDeclareVariable(float, t_hit, rtIntersectionDistance, );
//rtDeclareVariable(float3, tangent, attribute tangent, );
//rtDeclareVariable(float3, bitangent, attribute bitangent, );

struct PathResult{
	float4 result;
	float4 atenuation;
	float3 position;
	float3 direction;
	unsigned int depth;
	unsigned int seed;
	bool count_emissive;
	bool finished;
};

rtDeclareVariable(PathResult, current_path_result, rtPayload, );
rtDeclareVariable(optix::Ray, current_ray, rtCurrentRay, );

__device__ __inline__ void calc_direct_light(){

}

RT_PROGRAM void closest_hit(){
	//because we calculate direct lighting in every point of the path,
	//when first diffuse material is hit we stop counting emmisive contributions
	current_path_result.count_emissive=false;
	//calculate diffuse and specular probabilities.
	float pdiff=(Kd.x+Kd.y+Kd.z)*0.33333333333333333333333333333f;
	float pspec=(Ks.x+Ks.y+Ks.z)*0.33333333333333333333333333333f;
	pspec*=fminf(1.f, optix::dot(current_ray.direction, shading_normal)*(shininess+2.f)/(shininess+1.f));

	//randomly select the type of contribution
	float r=rnd(current_path_result.seed);
	if(r<pdiff+pspec){
		//select diffuse sample
		if(r<pdiff){
			float u1=rnd(current_path_result.seed);
			float u2=rnd(current_path_result.seed);
			float3 dir;
			optix::cosine_sample_hemisphere(u1, u2, dir);
			optix::Onb onb(shading_normal);
			onb.inverse_transform(dir);

			current_path_result.atenuation *= Kd/pdiff;
			current_path_result.direction = dir;

		}
		//select specular sample
		else {
			float u1=rnd(current_path_result.seed);
			float u2=rnd(current_path_result.seed);
			float3 dir;
			dir.x = sqrtf(1-powf(u1, 2.f/(shininess+1.f)))*cosf(M_2_PIf*u2);
			dir.y = sqrtf(1-powf(u1, 2.f/(shininess+1.f)))*sinf(M_2_PIf*u2);
			dir.z = powf(u1, 1.f/(shininess+1.f));
			optix::Onb onb(optix::reflect(current_ray.direction, shading_normal));
			onb.inverse_transform(dir);

			float intensity=optix::dot(dir, shading_normal);
			//verify if sampled direction is above surface
			if(intensity>0.f){
				current_path_result.atenuation*= ((shininess+2.f)/(shininess+1.f)) * (Ks/pspec) * optix::dot(dir, shading_normal);
				current_path_result.direction=dir;
			}
			else{
				current_path_result.finished=true;
			}
		}
	}
	//consider that photon is absorbed and finish path
	else{
		current_path_result.finished=true;
	}

}
