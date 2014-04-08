#include <optix_world.h>
#include "commonStructs.h"
#include "random.h"
#include "sphere_light.h"

using namespace optix;

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

struct ShadowResult{
	bool in_shadow;
};

rtDeclareVariable(float, t_hit, rtIntersectionDistance, );
rtDeclareVariable(optix::Ray, current_ray, rtCurrentRay, );

//ray payloads
rtDeclareVariable(PathResult, current_path_result, rtPayload, );
rtDeclareVariable(ShadowResult, current_shadow_result, rtPayload, );

//kernel dimensions
rtDeclareVariable(uint2, launch_index, rtLaunchIndex, );
rtDeclareVariable(uint2, launch_dim,   rtLaunchDim, );

//camera properties
rtDeclareVariable(float3, eye, , );
rtDeclareVariable(float3, U, , );
rtDeclareVariable(float3, V, , );
rtDeclareVariable(float3, W, , );
//lens (for depth of field)
rtDeclareVariable(float, lens_radius, , );
rtDeclareVariable(float, focal_dist, , );

//frame number to make sure result is different every frame
rtDeclareVariable(int, frame, , );
//samples for stratified sampling
rtDeclareVariable(int, sqrt_num_samples, , )=2;

//output buffer
rtBuffer<float4, 2> output;

//top object to start tracing rays
rtDeclareVariable(rtObject, top_object, , );

RT_PROGRAM void camera(){
	unsigned int seed = tea<16>(launch_dim.x*launch_index.y+launch_index.x, frame);

	float2 inv_screen=1.f/(make_float2(launch_dim)) *2.f;
	float2 pixel = (make_float2(launch_index)) * inv_screen - 1.f;
	float2 jitter_scale = inv_screen / sqrt_num_samples;

	int samples_per_pixel = sqrt_num_samples * sqrt_num_samples;

	float4 result = make_float4(0.0f);

	do{
		int x = samples_per_pixel%sqrt_num_samples;
		int y = samples_per_pixel/sqrt_num_samples;
		float2 jitter = make_float2(x-rnd(seed), y-rnd(seed));
		float2 d = pixel + jitter*jitter_scale;
		float3 ray_origin = eye;
		float3 ray_direction = normalize(d.x * U + d.y * V + W);

		PathResult ray_result;
		ray_result.atenuation=make_float4(1.f);
		ray_result.count_emissive=true;
		ray_result.depth=0;
		ray_result.result=make_float4(0.f);
		ray_result.seed=seed;
		ray_result.finished=false;

		for(;;){

			Ray ray = optix::make_Ray(ray_origin, ray_direction, PathRay, 0.001, RT_DEFAULT_MAX);
			rtTrace(top_object, ray, ray_result);

			if(ray_result.finished)
				break;

			ray_origin=ray_result.position;
			ray_direction=ray_result.direction;

		}

		result+=ray_result.result;
		seed=ray_result.seed;

	}while(--samples_per_pixel);

	result/=sqrt_num_samples * sqrt_num_samples;

	if(frame>1){
		float a = 1.f/float(frame);
		float b = float(frame-1)*a;
		float4 old_color=output[launch_index];
		output[launch_index]=a*result+b*old_color;
	}
	else{
		output[launch_index]=result;
	}

}

RT_PROGRAM void exception(){
	rtPrintExceptionDetails();
}

RT_PROGRAM void path_miss(){
	current_path_result.finished = true;
}

#include "material.h"

__device__ __inline__ void calc_direct_light(){

}

RT_PROGRAM void glossy_shading(){
	//because we calculate direct lighting in every point of the path,
	//when first diffuse material is hit we stop counting emmisive contributions
	current_path_result.count_emissive=false;
	//calculate diffuse and specular probabilities.
	float pdiff=(Kd.x+Kd.y+Kd.z)*0.33333333333333333333333333333f;
	float pspec=(Ks.x+Ks.y+Ks.z)*0.33333333333333333333333333333f;
	pspec*=fminf(1.f, optix::dot(current_ray.direction, shading_normal)*(Ns+2.f)/(Ns+1.f));

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
			dir.x = sqrtf(1-powf(u1, 2.f/(Ns+1.f)))*cosf(M_2_PIf*u2);
			dir.y = sqrtf(1-powf(u1, 2.f/(Ns+1.f)))*sinf(M_2_PIf*u2);
			dir.z = powf(u1, 1.f/(Ns+1.f));
			optix::Onb onb(optix::reflect(current_ray.direction, shading_normal));
			onb.inverse_transform(dir);

			float intensity=optix::dot(dir, shading_normal);
			//verify if sampled direction is above surface
			if(intensity>0.f){
				current_path_result.atenuation*= ((Ns+2.f)/(Ns+1.f)) * (Ks/pspec) * optix::dot(dir, shading_normal);
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

RT_PROGRAM void path_ignore_alpha(){
	float4 color=Kd*tex2D(map_Kd, texCoord.x, texCoord.y);
	if(color.w == 0.f) rtIgnoreIntersection();
}


RT_PROGRAM void shadow_probe(){
	float4 color=Kd*tex2D(map_Kd, texCoord.x, texCoord.y);
	if(color.w == 0.f) rtIgnoreIntersection();
	else{
		current_shadow_result.in_shadow=true;
		rtTerminateRay();
	}
}




