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

#define MIN_DEPTH 3

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


	current_path_result.count_emissive=false;
	//calculate diffuse and specular probabilities.
	float4 diff_coef = Kd*tex2D(map_Kd, texCoord.x, texCoord.y);
	float4 spec_coef = Ks*tex2D(map_Ks, texCoord.x, texCoord.y);

	float3 position = current_ray.origin + current_ray.direction * t_hit;

	float3 ffnormal = optix::faceforward(shading_normal, -current_ray.direction, shading_normal);

	//check refraction
	float3 refracted = make_float3(0.f);
	float reflectance;
	if(Ni>0 && optix::refract(refracted, current_ray.direction, shading_normal, Ni)){
		float cos_theta = dot(current_ray.direction, shading_normal);
		if(cos_theta<0.f)
			cos_theta = -cos_theta;
		else
			cos_theta = dot(refracted, shading_normal);
		float r0 = powf((1.f-Ni)/(1.f+Ni), 2.f);
		reflectance = r0 + (1.f-r0)*optix::fresnel_schlick(cos_theta);

	}
	else reflectance = 1.f;

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

		float intensity = dot(ffnormal, dir);

		if(intensity>0.f){

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
				float4 diff_res = diff_coef ;
				float spec_intensity;
				if(dot(-current_ray.direction, shading_normal)>0.f)
					spec_intensity = fmaxf(dot(dir, reflect(current_ray.direction, ffnormal)), 0.f);
				else{
					if(optix::length(refracted)>0.f){
						spec_intensity = fmaxf(dot(dir, refracted), 0.f);
					}
				}
				spec_intensity = powf(spec_intensity, Ns);
				float4 spec_res = spec_coef * (Ns +2.f)* 0.5f * spec_intensity;
				current_path_result.result += (diff_res + spec_res) * M_1_PIf * lights[i].color * intensity * current_path_result.atenuation * (1.f - sqrtf(1.f - powf(radius/length(position-center), 2.f))) * 2.f * M_PIf;
			}
		}
	}



	float3 pkd = make_float3(diff_coef*current_path_result.atenuation);
	float3 pks = make_float3(spec_coef*current_path_result.atenuation);

	float pdiff=(pkd.x+pkd.y+pkd.z)*0.33333333333333333333333333333f;
	float pspec=(pks.x+pks.y+pks.z)*0.33333333333333333333333333333f;
	pspec*=fminf(1.f, optix::dot(current_ray.direction, ffnormal)*(Ns+2.f)/(Ns+1.f));

	//randomly select the type of contribution
	float r=rnd(current_path_result.seed);
	if(current_path_result.depth < MIN_DEPTH || pdiff+pspec>1.f){
		float inv_p = 1.f/(pdiff+pspec);
		pdiff*=inv_p;
		pspec*=inv_p;
	}

	float preflect = rnd(current_path_result.seed);
	if(preflect < reflectance){

		if(r<pdiff+pspec){
			//select diffuse sample
			if(r<pdiff){

				float u1=rnd(current_path_result.seed);
				float u2=rnd(current_path_result.seed);
				float3 dir;
				optix::cosine_sample_hemisphere(u1, u2, dir);
				optix::Onb onb(ffnormal);
				onb.inverse_transform(dir);

				current_path_result.atenuation *= diff_coef/pdiff;
				current_path_result.direction = dir;
				current_path_result.position = position;

			}
			//select specular sample

			else {
				float u1=rnd(current_path_result.seed);
				float u2=rnd(current_path_result.seed);
				float3 dir;
				dir.x = sqrtf(1-powf(u1, 2.f/(Ns+1.f)))*cosf(M_2_PIf*u2);
				dir.y = sqrtf(1-powf(u1, 2.f/(Ns+1.f)))*sinf(M_2_PIf*u2);
				dir.z = powf(u1, 1.f/(Ns+1.f));
				optix::Onb onb(optix::reflect(current_ray.direction, ffnormal));
				onb.inverse_transform(dir);

				float intensity=optix::dot(dir, ffnormal);
				//verify if sampled direction is above surface
				if(intensity>0.f){
					current_path_result.atenuation*= ((Ns+2.f)/(Ns+1.f)) * (spec_coef/pspec) * intensity;
					current_path_result.direction=dir;
					current_path_result.position = position;
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

	else{

		if(r<pdiff+pspec){
			//select diffuse sample
			if(false){//r<pdiff){

				float u1=rnd(current_path_result.seed);
				float u2=rnd(current_path_result.seed);
				float3 dir;
				optix::cosine_sample_hemisphere(u1, u2, dir);
				optix::Onb onb(-ffnormal);
				onb.inverse_transform(dir);

				current_path_result.atenuation *= diff_coef/pdiff;
				current_path_result.direction = dir;
				current_path_result.position = position;

			}
			//select specular sample

			else {

				float u1=rnd(current_path_result.seed);
				float u2=rnd(current_path_result.seed);
				float3 dir;
				dir.x = sqrtf(1-powf(u1, 2.f/(Ns+1.f)))*cosf(M_2_PIf*u2);
				dir.y = sqrtf(1-powf(u1, 2.f/(Ns+1.f)))*sinf(M_2_PIf*u2);
				dir.z = powf(u1, 1.f/(Ns+1.f));
				optix::Onb onb(refracted);
				onb.inverse_transform(dir);

				float intensity;
				intensity=optix::dot(dir, -ffnormal);


				//verify if sampled direction is above surface
				if(intensity>0.f){
					current_path_result.atenuation*= ((Ns+2.f)/(Ns+1.f)) * (spec_coef/pspec) * intensity;
					current_path_result.direction=dir;
					current_path_result.position = position;
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
	if(current_path_result.count_emissive) current_path_result.result += light_color * current_path_result.atenuation;
	current_path_result.finished=true;
}

RT_PROGRAM void shadow_probe_light(){
	current_shadow_result.in_shadow=true;
	rtTerminateRay();
}


