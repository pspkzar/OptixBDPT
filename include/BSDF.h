/*
 * BSDF.h
 *
 *  Created on: 14 de Dez de 2014
 *      Author: cesar
 */

#ifndef BSDF_H_
#define BSDF_H_

#include <optix_world.h>
#include <optixu/optixpp_namespace.h>
#include <optixu/optixu_math_namespace.h>

#ifndef OPTIXU_INLINE
#  define OPTIXU_INLINE_DEFINED 1
#  define OPTIXU_INLINE __forceinline__
#endif

namespace rt {

struct BSDF_Sample {
	float type;
	float dir[2];
};

struct LightSample{
	float light;
	float point[2];
};

struct BSDF {

	optix::float4 Ke;
	optix::float4 Kd;
	optix::float4 Ks;
	float Ns;
	float Ni;

	OPTIXU_INLINE RT_HOSTDEVICE float sample(optix::float3& in,
			optix::float3& n, optix::float3& out, optix::float4 &r,
			BSDF_Sample &s) {
		optix::float3 refracted = optix::make_float3(0.f);
		//Measure reflectance and refractance
		float reflectance;
		if (Ni > 0.f && optix::refract(refracted, in, n, Ni)) {
			float cos_theta = optix::dot(in, n);
			if (cos_theta < 0.f)
				cos_theta = -cos_theta;
			else
				cos_theta = optix::dot(refracted, n);
			float r0 = ((1.f - Ni) / (1.f + Ni)) * ((1.f - Ni) / (1.f + Ni));
			reflectance = r0 + (1.f - r0) * powf(1.f - cos_theta, 5.f);
		} else
			reflectance = 1.f;
		//face forward normal
		optix::float3 ffnormal = optix::faceforward(n, -in, n);
		//calculate scattering type probabilities
		float pdiff = optix::luminance(optix::make_float3(Kd));
		float pspec = optix::luminance(optix::make_float3(Ks));
		pspec *= fminf(1.f,
				optix::dot(-in, ffnormal) * (Ns + 2.f) / (Ns + 1.f));
		//select between reflection and refraction
		optix::float3 spec_dir;
		float pdf;
		float type = s.type;
		if (type < reflectance) {
			spec_dir = optix::reflect(in, ffnormal);
			pdf = reflectance;
			r = optix::make_float4(reflectance);
			type /= reflectance;
		} else {
			spec_dir = refracted;
			ffnormal = -ffnormal;
			pdf = 1.f - reflectance;
			r = optix::make_float4(1.f - reflectance);
			type -= reflectance;
			type /= (1.f - reflectance);
		}
		//select between diffuse and specular
		if (type < pdiff + pspec) {
			if (type < pdiff) {
				//sample diffuse outward direction
				optix::cosine_sample_hemisphere(s.dir[0], s.dir[1], out);
				optix::Onb onb(ffnormal);
				onb.inverse_transform(out);
			} else {
				//sample specular outward direction
				float u1 = s.dir[0];
				float u2 = s.dir[1];
				out.x = sqrtf(1 - powf(u1, 2.f / (Ns + 1.f)))
						* cosf(M_2_PIf * u2);
				out.y = sqrtf(1 - powf(u1, 2.f / (Ns + 1.f)))
						* sinf(M_2_PIf * u2);
				out.z = powf(u1, 1.f / (Ns + 1.f));
				optix::Onb onb(spec_dir);
				onb.inverse_transform(out);
			}
			//calculate atenuation and pdf wrt solid angle
			float spec_intensity = fmaxf(powf(optix::dot(out, spec_dir), Ns),
					0.f);
			float intensity = optix::dot(out, ffnormal);

			if (intensity > 0.f) {
				r *= (Kd * M_1_PIf
						+ Ks * (Ns + 2.f) * 0.5f * M_1_PIf * spec_intensity)* intensity;
				pdf *= (pdiff * M_1_PIf * intensity
						+ pspec * (Ns + 1.f) * 0.5f * M_1_PIf * spec_intensity);
			} else
				pdf = 0.f;
		} else
			pdf = 0.f;
		return pdf;
	}

	OPTIXU_INLINE RT_HOSTDEVICE float evaluate(optix::float3& in,
			optix::float3& n, optix::float3& out, optix::float4 &r) {
		optix::float3 refracted = optix::make_float3(0.f);
		//Measure reflectance and refractance
		float reflectance;
		if (Ni > 0.f && optix::refract(refracted, in, n, Ni)) {
			float cos_theta = optix::dot(in, n);
			if (cos_theta < 0.f)
				cos_theta = -cos_theta;
			else
				cos_theta = optix::dot(refracted, n);
			float r0 = ((1.f - Ni) / (1.f + Ni)) * ((1.f - Ni) / (1.f + Ni));
			reflectance = r0 + (1.f - r0) * powf(1.f - cos_theta, 5.f);
		} else
			reflectance = 1.f;
		//face forward normal
		optix::float3 ffnormal = optix::faceforward(n, -in, n);

		float pdiff = optix::luminance(optix::make_float3(Kd));
		float pspec = optix::luminance(optix::make_float3(Ks));
		pspec *= fminf(1.f,
				optix::dot(-in, ffnormal) * (Ns + 2.f) / (Ns + 1.f));

		float pdf;
		optix::float3 spec_dir;

		if (optix::dot(ffnormal, out) > 0.f) {
			r = optix::make_float4(reflectance);
			pdf = reflectance;
			spec_dir = optix::reflect(in, ffnormal);
		} else {
			r = optix::make_float4(1.f - reflectance);
			pdf = 1.f - reflectance;
			spec_dir = refracted;
			ffnormal = -ffnormal;
		}
		if (pdf > 0.f) {
			float spec_intensity = fmaxf(powf(optix::dot(out, spec_dir), Ns),
					0.f);
			float intensity = optix::dot(out, ffnormal);
			r *= (Kd * M_1_PIf
					+ Ks * (Ns + 2.f) * 0.5f * M_1_PIf * spec_intensity)* intensity;
			pdf *= (pdiff * M_1_PIf * intensity
					+ pspec * (Ns + 1.f) * 0.5f * M_1_PIf * spec_intensity);
		}
		return pdf;
	}
};

}

#ifdef OPTIXU_INLINE_DEFINED
#  undef OPTIXU_INLINE_DEFINED
#  undef OPTIXU_INLINE
#endif

#endif /* BSDF_H_ */
