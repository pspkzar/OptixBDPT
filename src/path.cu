#include <optix_world.h>

#include "random.h"
#include "sphere_light.h"

#include "commonStructs.h"

using namespace optix;



struct PathResult{
	float4 result;
	float4 atenuation;
	float3 position;
	float3 direction;
	float weight;
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
rtDeclareVariable(LightPathResult, current_light_result, rtPayload, );

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

//light path buffer
rtBuffer<LightPathResult, 3> lightPathBuffer;

//output buffer
rtBuffer<float4, 2> output;

//top object to start tracing rays
rtDeclareVariable(rtObject, top_object, , );


rtDeclareVariable(float, scene_epsilon, , )=0.01f;


RT_PROGRAM void light_path_gen(){
	unsigned int seed = tea<16>(launch_dim.x*launch_index.y+launch_index.x, frame);
	//TODO calculate light path
	SphereLight l = lights[0];
	float l1 = rnd(seed)*2.f-1.f;
	float l2 = rnd(seed)*2.f-1.f;
	while((l1*l1+l2*l2)>=1.f){
		l1 = rnd(seed)*2.f-1.f;
		l2 = rnd(seed)*2.f-1.f;
	}

	float3 light_normal;
	light_normal.x = 2.f * l1 * sqrtf(1.f - l1*l1 - l2*l2);
	light_normal.y = 2.f * l2 * sqrtf(1.f - l1*l1 - l2*l2);
	light_normal.z = 1.f - 2.f * (l1*l1 + l2*l2);

	float3 light_point = make_float3(l.pos) + l.pos.w * light_normal;

	l1 = rnd(seed);
	l2 = rnd(seed);

	float3 light_dir;
	optix::cosine_sample_hemisphere(l1, l2, light_dir);
	optix::Onb onb_light(light_normal);
	onb_light.inverse_transform(light_dir);

	Ray light_ray = optix::make_Ray(light_point, light_dir, LightPathRay, scene_epsilon, RT_DEFAULT_MAX);

	LightPathResult result0;
	result0.radiance=l.color;
	result0.In=light_dir;

	rtTrace(top_object, light_ray, result0);
	lightPathBuffer[make_uint3(launch_index, 0)]=result0;

	int i=1;

	while((i < LIGHT_PATH_LENGTH) && (!lightPathBuffer[make_uint3(launch_index, i-1)].missed)){


		float4 diff_coef = lightPathBuffer[make_uint3(launch_index, i-1)].Kd;
		float4 spec_coef = lightPathBuffer[make_uint3(launch_index, i-1)].Ks;

		float3 position = lightPathBuffer[make_uint3(launch_index, i-1)].position;

		float3 ffnormal = optix::faceforward(lightPathBuffer[make_uint3(launch_index, i-1)].normal, -lightPathBuffer[make_uint3(launch_index, i-1)].In, lightPathBuffer[make_uint3(launch_index, i-1)].normal);

		//check refraction
		float3 refracted = make_float3(0.f);
		float reflectance;
		if(lightPathBuffer[make_uint3(launch_index, i-1)].Ni>0.f && optix::refract(refracted, lightPathBuffer[make_uint3(launch_index, i-1)].In, lightPathBuffer[make_uint3(launch_index, i-1)].normal, lightPathBuffer[make_uint3(launch_index, i-1)].Ni)){
			float cos_theta = dot(lightPathBuffer[make_uint3(launch_index, i-1)].In, lightPathBuffer[make_uint3(launch_index, i-1)].normal);
			if(cos_theta<0.f)
				cos_theta = -cos_theta;
			else
				cos_theta = dot(refracted, lightPathBuffer[make_uint3(launch_index, i-1)].normal);
			float r0 = ((1.f-lightPathBuffer[make_uint3(launch_index, i-1)].Ni)/(1.f+lightPathBuffer[make_uint3(launch_index, i-1)].Ni))*((1.f-lightPathBuffer[make_uint3(launch_index, i-1)].Ni)/(1.f+lightPathBuffer[make_uint3(launch_index, i-1)].Ni));
			reflectance = r0 + (1.f-r0)*powf(1.f-cos_theta, 5.f);

		}
		else reflectance = 1.f;



		float pdiff=(diff_coef.x+diff_coef.y+diff_coef.z)*0.33333333333333333333333333333f;
		float pspec=(spec_coef.x+spec_coef.y+spec_coef.z)*0.33333333333333333333333333333f;
		pspec*=fminf(1.f, optix::dot(-lightPathBuffer[make_uint3(launch_index, i-1)].In, ffnormal)*(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+2.f)/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f));

		//randomly select the type of contribution
		float r=rnd(seed);
		if(i < MIN_DEPTH || pdiff+pspec>1.f){
			float inv_p = 1.f/(pdiff+pspec);
			pdiff*=inv_p;
			pspec*=inv_p;
		}

		float p_reflect = rnd(seed);

		if(p_reflect<reflectance){
			if(r<pdiff+pspec){
				if(r<pdiff){
					LightPathResult result;
					result.radiance = lightPathBuffer[make_uint3(launch_index, i-1)].radiance * diff_coef/pdiff;
					float3 new_dir;
					optix::cosine_sample_hemisphere(rnd(seed), rnd(seed), new_dir);
					optix::Onb onb(ffnormal);
					onb.inverse_transform(new_dir);
					result.In=new_dir;
					Ray new_ray = optix::make_Ray(lightPathBuffer[make_uint3(launch_index, i-1)].position, lightPathBuffer[make_uint3(launch_index, i)].In, LightPathRay, scene_epsilon, RT_DEFAULT_MAX);
					rtTrace(top_object, new_ray, result);
					lightPathBuffer[make_uint3(launch_index, i)]=result;
				}
				else{
					float u1=rnd(seed);
					float u2=rnd(seed);
					float3 dir;
					dir.x = sqrtf(1-powf(u1, 2.f/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f)))*cosf(M_2_PIf*u2);
					dir.y = sqrtf(1-powf(u1, 2.f/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f)))*sinf(M_2_PIf*u2);
					dir.z = powf(u1, 1.f/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f));
					float3 reflected = optix::reflect(lightPathBuffer[make_uint3(launch_index, i-1)].In, ffnormal);
					optix::Onb onb(reflected);
					onb.inverse_transform(dir);
					LightPathResult result;
					result.In=dir;
					float intensity=optix::dot(dir, ffnormal);

					//verify if sampled direction is above surface
					if(intensity>0.f){
						result.radiance =lightPathBuffer[make_uint3(launch_index, i-1)].radiance * ((lightPathBuffer[make_uint3(launch_index, i-1)].Ns+2.f)/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f)) * (spec_coef/pspec) * intensity;
						Ray new_ray = optix::make_Ray(lightPathBuffer[make_uint3(launch_index, i-1)].position, lightPathBuffer[make_uint3(launch_index, i)].In, LightPathRay, scene_epsilon, RT_DEFAULT_MAX);
						rtTrace(top_object, new_ray, result);
						lightPathBuffer[make_uint3(launch_index, i)]=result;
					}
					else{
						lightPathBuffer[make_uint3(launch_index, i)].missed=true;
					}
				}
			}
			else{
				lightPathBuffer[make_uint3(launch_index, i)].missed=true;
			}
		}
		else{

			if(r<pdiff+pspec){
				if(r<pdiff){
					LightPathResult result;
					result.radiance = lightPathBuffer[make_uint3(launch_index, i-1)].radiance * diff_coef/pdiff;
					float3 new_dir;
					optix::cosine_sample_hemisphere(rnd(seed), rnd(seed), new_dir);
					optix::Onb onb(-ffnormal);
					onb.inverse_transform(new_dir);
					result.In=new_dir;
					Ray new_ray = optix::make_Ray(lightPathBuffer[make_uint3(launch_index, i-1)].position, lightPathBuffer[make_uint3(launch_index, i)].In, LightPathRay, scene_epsilon, RT_DEFAULT_MAX);
					rtTrace(top_object, new_ray, result);
					lightPathBuffer[make_uint3(launch_index, i)]=result;
				}
				else{
					LightPathResult result;
					float u1=rnd(seed);
					float u2=rnd(seed);
					float3 dir;
					dir.x = sqrtf(1-powf(u1, 2.f/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f)))*cosf(M_2_PIf*u2);
					dir.y = sqrtf(1-powf(u1, 2.f/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f)))*sinf(M_2_PIf*u2);
					dir.z = powf(u1, 1.f/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f));
					optix::Onb onb(refracted);
					onb.inverse_transform(dir);

					result.In=dir;
					float intensity=optix::dot(-dir, ffnormal);

					//verify if sampled direction is above surface
					if(intensity>0.f){
						result.radiance =lightPathBuffer[make_uint3(launch_index, i-1)].radiance * ((lightPathBuffer[make_uint3(launch_index, i-1)].Ns+2.f)/(lightPathBuffer[make_uint3(launch_index, i-1)].Ns+1.f)) * (spec_coef/pspec) * intensity;
						Ray new_ray = optix::make_Ray(lightPathBuffer[make_uint3(launch_index, i-1)].position, lightPathBuffer[make_uint3(launch_index, i)].In, LightPathRay, scene_epsilon, RT_DEFAULT_MAX);
						rtTrace(top_object, new_ray, result);
						lightPathBuffer[make_uint3(launch_index, i)]=result;
					}
					else{
						lightPathBuffer[make_uint3(launch_index, i)].missed=true;
					}
				}
			}
			else{
				lightPathBuffer[make_uint3(launch_index, i)].missed=true;
			}
		}

		i++;
	}

}

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
		ray_result.weight=1.f;

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


RT_PROGRAM void lightPathTrace(){
	current_light_result.Kd=Kd*tex2D(map_Kd, texCoord.x, texCoord.y);
	current_light_result.Ks=Ks*tex2D(map_Ks, texCoord.x, texCoord.y);
	current_light_result.Ni=Ni;
	current_light_result.Ns=Ns;
	current_light_result.normal=shading_normal;
	current_light_result.position=current_ray.origin + current_ray.direction * t_hit;
	current_light_result.missed=false;
}

RT_PROGRAM void lightPathMiss(){
	current_light_result.missed=true;
}

RT_PROGRAM void lightPathHitLight(){
	current_light_result.missed=true;
}

RT_PROGRAM void glossy_shading(){



	//because we calculate direct lighting in every point of the path,
	//when first diffuse material is hit we stop counting emmisive contributions
	current_path_result.count_emissive=false;
	//calculate diffuse and specular probabilities.
	float4 diff_coef = Kd*tex2D(map_Kd, texCoord.x, texCoord.y);
	float4 spec_coef = Ks*tex2D(map_Ks, texCoord.x, texCoord.y);

	float dc = (diff_coef.x + diff_coef.y + diff_coef.z)*0.33333333333333333333333333333f;
	float ds = (spec_coef.x + spec_coef.y + spec_coef.z)*0.33333333333333333333333333333f;




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
		float r0 = ((1.f-Ni)/(1.f+Ni))*((1.f-Ni)/(1.f+Ni));
		reflectance = r0 + (1.f-r0)*powf(1-cos_theta, 5.f);

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

		float intensity = dot(shading_normal, dir);

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
				/*
				float spec_intensity;
				if(dot(dir, ffnormal)>0.f)
					spec_intensity = fmaxf(dot(dir, reflect(current_ray.direction, ffnormal)), 0.f);
				else{
					if(optix::length(refracted)>0.f){
						spec_intensity = fmaxf(dot(dir, refracted), 0.f);
					}
				}
				spec_intensity = powf(spec_intensity, Ns);
				float4 spec_res = spec_coef * (Ns +2.f)* 0.5f * spec_intensity;*/
				current_path_result.result += ((diff_res) * M_1_PIf * lights[i].color * intensity * current_path_result.atenuation * (1.f - sqrtf(1.f - powf(radius/length(position-center), 2.f))) * 2.f * M_PIf) * current_path_result.weight;
			}
		}
	}

	float weight = (ds/(dc+ds))*.5f + 0.5f;

	if(weight<1.f){
		float4 light_path_contribution=make_float4(0.f);
		for(int i=0 ; i<LIGHT_PATH_LENGTH; i++){
			uint3 lindex = make_uint3(launch_index, i);
			if(lightPathBuffer[lindex].missed) break;

			float3 dir = lightPathBuffer[lindex].position - position;
			float tdist = length(dir);
			dir = normalize(dir);

			Ray shadow_r = optix::make_Ray(position, dir, ShadowRay, scene_epsilon, tdist);
			ShadowResult sres;
			sres.in_shadow=false;

			rtTrace(top_object, shadow_r, sres);
			if(!sres.in_shadow){


				//check refraction
				float3 out_refracted = make_float3(0.f);
				float out_reflectance;
				if(lightPathBuffer[lindex].Ni>0.f && optix::refract(out_refracted, lightPathBuffer[lindex].In, lightPathBuffer[lindex].normal, lightPathBuffer[lindex].Ni)){
					float cos_theta = dot(lightPathBuffer[lindex].In, lightPathBuffer[lindex].normal);
					if(cos_theta<0.f)
						cos_theta = -cos_theta;
					else
						cos_theta = dot(out_refracted, lightPathBuffer[lindex].normal);
					float r0 = ((1.f-lightPathBuffer[lindex].Ni)/(1.f+lightPathBuffer[lindex].Ni))*((1.f-lightPathBuffer[lindex].Ni)/(1.f+lightPathBuffer[lindex].Ni));

					out_reflectance = r0 + (1.f-r0)*powf(1.f-cos_theta, 5.f);

				}
				else out_reflectance = 1.f;

				float3 spec_dir;
				float spec_intensity;
				if(dot(dir, lightPathBuffer[lindex].In)>0.f){
					spec_dir=optix::reflect(lightPathBuffer[lindex].In, lightPathBuffer[lindex].normal);
					spec_intensity=fmaxf(0.f,powf(dot(spec_dir, -dir), lightPathBuffer[lindex].Ns));
				}
				else{
					if(optix::length(out_refracted)>0.f){
						spec_intensity=fmaxf(0.f,powf(dot(out_refracted, -dir), lightPathBuffer[lindex].Ns));
					}
					else{
						spec_intensity=0.f;
					}
				}
				float out_intensity = abs(dot(lightPathBuffer[lindex].In, lightPathBuffer[lindex].normal));

				float4 out_rad_diff = lightPathBuffer[lindex].radiance * lightPathBuffer[lindex].Kd * M_1_PIf;;
				float4 out_rad_spec = lightPathBuffer[lindex].radiance * lightPathBuffer[lindex].Ks * spec_intensity * (lightPathBuffer[lindex].Ns + 2.f) * 0.5 * M_1_PIf;

				float4 out_rad = (out_rad_diff+out_rad_spec) * out_intensity;
				if(dot(dir, lightPathBuffer[lindex].In)>0.f) out_rad *= out_reflectance;
				else out_rad *= (1.f - out_reflectance);


				float in_intensity = abs(dot(dir, ffnormal));


				float in_spec_intensity;
				if(dot(current_ray.direction, dir)<0.f){
					in_spec_intensity = fmaxf(0.f, powf(dot(optix::reflect(current_ray.direction, ffnormal),dir), Ns));
				}
				else{

					if(optix::length(refracted)>0.f){
						in_spec_intensity = fmaxf(0.f, powf(dot(refracted, dir), Ns));
					}
					else{
						in_spec_intensity=0.f;
					}
				}

				float4 in_rad_diff = out_rad * diff_coef * M_1_PIf;
				float4 in_rad_spec = out_rad * spec_coef * in_spec_intensity * (Ns + 2) * 0.5 * M_1_PIf;

				float4 in_rad = (in_rad_diff+in_rad_spec) * in_intensity * fminf(abs(dot(dir, lightPathBuffer[lindex].normal)) / (tdist*tdist), 1.f);
				if(dot(current_ray.direction, dir)<0.f) in_rad *= reflectance;
				else in_rad *= 1.f - reflectance;

				current_path_result.result+=in_rad * current_path_result.weight * (1.f-weight);
				light_path_contribution+=in_rad * current_path_result.weight * (1.f-weight);
			}
		}
		if(light_path_contribution.x+light_path_contribution.y+light_path_contribution.z==0.f){
			weight=1.f;
		}
	}

	if(weight==0.f) {
		current_path_result.finished=true;
		return;
	}

	current_path_result.weight*=weight;

	float3 pkd = make_float3(diff_coef*current_path_result.atenuation);
	float3 pks = make_float3(spec_coef*current_path_result.atenuation);

	float pdiff=(pkd.x+pkd.y+pkd.z)*0.33333333333333333333333333333f;
	float pspec=(pks.x+pks.y+pks.z)*0.33333333333333333333333333333f;
	pspec*=fminf(1.f, optix::dot(-current_ray.direction, ffnormal)*(Ns+2.f)/(Ns+1.f));

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
				current_path_result.count_emissive=true;
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
			if(r<pdiff){

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
				current_path_result.count_emissive=true;
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

	if(current_path_result.count_emissive) current_path_result.result += light_color * current_path_result.atenuation*current_path_result.weight;
	current_path_result.finished=true;
}

RT_PROGRAM void shadow_probe_light(){
	current_shadow_result.in_shadow=true;
	rtTerminateRay();
}


