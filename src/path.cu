#include <optix_world.h>
#include "commonStructs.h"
#include "random.h"
#include "sphere_light.h"
#include "BSDF.h"

using namespace optix;

struct PathResult{
	float4 result;
	float4 atenuation;
	float3 position;
	float3 direction;
	unsigned int depth;
	unsigned int seed;
	float prob;
	bool count_emissive;
	bool finished;
};

struct ShadowResult{
	bool in_shadow;
};

#define MIN_DEPTH 1

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
rtDeclareVariable(float, lens_radius, , )=0.0f;
rtDeclareVariable(float, focal_dist, , )=150.f;

//frame number to make sure result is different every frame
rtDeclareVariable(int, frame, , );
//samples for stratified sampling
rtDeclareVariable(int, sqrt_num_samples, , )=1;

//output buffer
rtBuffer<float4, 2> output;

//top object to start tracing rays
rtDeclareVariable(rtObject, top_object, , );


rtDeclareVariable(float, scene_epsilon, , )=0.01f;

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

		float r = lens_radius * sqrtf(rnd(seed));
		float ang = 2.f * M_PIf * rnd(seed);

		float3 ray_origin = eye + r * ( U * cosf(ang) + V * sinf(ang));
		float3 ray_target = eye + (d.x * U + d.y * V + W) * focal_dist;
		float3 ray_direction = normalize(ray_target - ray_origin);


		PathResult ray_result;
		ray_result.atenuation=make_float4(1.f);
		ray_result.count_emissive=true;
		ray_result.depth=0;
		ray_result.result=make_float4(0.f);
		ray_result.seed=seed;
		ray_result.finished=false;
		ray_result.prob=1.f;

		for(;;){

			Ray ray = make_Ray(ray_origin, ray_direction, PathRay, scene_epsilon, RT_DEFAULT_MAX);
			rtTrace(top_object, ray, ray_result);

			if(ray_result.finished)
				break;

			ray_origin=ray_result.position;
			ray_direction=ray_result.direction;
			ray_result.depth++;

		}

		result+=ray_result.result;
		seed=ray_result.seed;

	}while(--samples_per_pixel);

	result/=sqrt_num_samples * sqrt_num_samples;


	if(frame>1){
		float a = 1.f/float(frame);
		float b = float(frame-1)*a;
		float4 old_color=output[launch_index];///(make_float4(1.f) - output[launch_index]);
		float4 new_color = a*result+b*old_color;
		output[launch_index]= new_color;///(new_color + make_float4(1.f));
	}
	else{
		output[launch_index]=result;///(result + make_float4(1.f));
	}

}

RT_PROGRAM void exception(){
	//output[launch_index]=make_float4(1.f);
	rtPrintExceptionDetails();
}

RT_PROGRAM void path_miss(){
	current_path_result.finished = true;
}

#include "material.h"



RT_PROGRAM void glossy_shading(){
	//because we calculate direct lighting in every point of the path,
	//when first diffuse material is hit we stop counting emmisive contributions


	current_path_result.count_emissive=true;
	//calculate diffuse and specular probabilities.
	float4 diff_coef = Kd*tex2D(map_Kd, texCoord.x, texCoord.y);
	float4 spec_coef = Ks*tex2D(map_Ks, texCoord.x, texCoord.y);

	float3 position = current_ray.origin + current_ray.direction * t_hit;

	BSDF bsdf;
	bsdf.Kd=diff_coef;
	bsdf.Ks=spec_coef;
	bsdf.Ni=Ni;
	bsdf.Ns=Ns;

	float3 ffnormal = optix::faceforward(shading_normal, -current_ray.direction, shading_normal);

	for(int i=0; i<lights.size(); i++){
		//sample light
		float3 center = make_float3(lights[i].pos);

		float3 w = normalize(center-position);
		float3 v = normalize(cross(w, ffnormal));
		float3 u = cross(v, w);

		float u1, u2;
		u1=rnd(current_path_result.seed);
		u2=rnd(current_path_result.seed);

		float cos_a = 1 - u1 + u1 * sqrtf(1-powf(lights[i].pos.w / length(position-center), 2.f));
		float sin_a = sqrtf(1-cos_a*cos_a);
		float phi = 2 * M_PIf * u2;

		float3 dir = u * cosf(phi) * sin_a + v * sinf(phi) * sin_a + w * cos_a;
		float4 r;
		float pdf = bsdf.evaluate(current_ray.direction, shading_normal, dir, r);

		if(pdf>0.f){

			float radius = lights[i].pos.w;

			float3 o = position - center;

			float b = dot(o, dir);
			float c = dot(o, o) - radius * radius;
			float disc = b * b - c;

			float sdisc = sqrtf(disc);
			float root1 = (-b -sdisc);

			Ray shadow_test = make_Ray(position, dir, ShadowRay, scene_epsilon, root1);
			ShadowResult s_res;
			s_res.in_shadow=false;
			rtTrace(top_object, shadow_test, s_res);

			if(!s_res.in_shadow){

				float plight = radius / length(o);
				plight*=plight;
				plight=sqrtf(1.f-plight);
				plight=2.f*M_PIf * (1.f - plight);
				plight=1.f/plight;

				float weight = plight;
				weight/=weight + pdf;

				current_path_result.result += weight * (r * lights[i].color * current_path_result.atenuation * (1.f - sqrtf(1.f - powf(radius/length(position-center), 2.f))) * 2.f * M_PIf);
			}
		}
	}

	BSDF_Sample sample;
	sample.type=rnd(current_path_result.seed);
	sample.dir[0]=rnd(current_path_result.seed);
	sample.dir[1]=rnd(current_path_result.seed);

	float4 r;
	float3 out;

	float pdf=bsdf.sample(current_ray.direction, shading_normal, out, r, sample);

	if(pdf>0.f){
		current_path_result.atenuation*=r;
		current_path_result.direction=out;
		current_path_result.position=position;
		current_path_result.prob=pdf;
	}
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

RT_PROGRAM void light_shading(){
	if(current_path_result.depth==0) {
		current_path_result.result += light.color * current_path_result.atenuation;
		current_path_result.finished=true;
		return;
	}

	float plight = light.pos.w / optix::length(current_ray.origin-make_float3(light.pos));
	plight*=plight;
	plight=sqrtf(1.f-plight);
	plight=2.f*M_PIf * (1.f - plight);
	plight=1.f/plight;

	float weight = current_path_result.prob;
	weight /= weight + plight;

	current_path_result.result += light.color * current_path_result.atenuation * weight;

	current_path_result.finished=true;
}

RT_PROGRAM void shadow_probe_light(){
	current_shadow_result.in_shadow=true;
	rtTerminateRay();
}


