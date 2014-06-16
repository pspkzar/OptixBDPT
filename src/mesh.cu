#include <optix_world.h>
#include <math_constants.h>
#include "mesh.h"

#define BUMP_INTENSITY 0.1f

#define TESS 4

using namespace optix;

rtDeclareVariable(float, t_hit, rtIntersectionDistance, );
rtDeclareVariable(optix::Ray, current_ray, rtCurrentRay, );

rtTextureSampler<float, 2> bump;

RT_PROGRAM void intersectMesh(int primIdx){
	//get indices
	int3 id=index_buffer[primIdx];
	//get vertices
	float3 v1=vertex_buffer[id.x];
	float3 v2=vertex_buffer[id.y];
	float3 v3=vertex_buffer[id.z];
	//intersect ray with triangle
	float3 n;
	float t, beta, gamma;
	if(intersect_triangle(current_ray, v1, v2, v3, n, t, beta, gamma))
	{
		//loading normals
		float3 n1=normal_buffer[id.x];
		float3 n2=normal_buffer[id.y];
		float3 n3=normal_buffer[id.z];

		float3 tmp_normal = (1.0f-beta-gamma)*n1 + beta*n2 +gamma*n3;


		//loading texCoords
		float2 tmp_texCoord;
		if(texCoord_buffer.size()==vertex_buffer.size()){
			float2 t1=texCoord_buffer[id.x];
			float2 t2=texCoord_buffer[id.y];
			float2 t3=texCoord_buffer[id.z];
			tmp_texCoord=(1.0f-beta-gamma)*t1 + beta*t2 +gamma*t3;
		}
		else
		{
			tmp_texCoord=make_float2(1.0f,0.0f);
		}

		float3 tmp_tangent, tmp_bitangent;

		if(tangent_buffer.size()==vertex_buffer.size()){
			float3 t1=tangent_buffer[id.x];
			float3 t2=tangent_buffer[id.y];
			float3 t3=tangent_buffer[id.z];

			float3 b1=bitangent_buffer[id.x];
			float3 b2=bitangent_buffer[id.y];
			float3 b3=bitangent_buffer[id.z];



			tmp_tangent=(1.0f-beta-gamma)*t1 + beta*t2 +gamma*t3;
			tmp_bitangent=(1.0f-beta-gamma)*b1 + beta*b2 +gamma*b3;


		}
		else{
			tmp_tangent=make_float3(0.f);
			tmp_bitangent=make_float3(0.f);
		}

		if((tangent_buffer.size()==vertex_buffer.size()) && (texCoord_buffer.size()==vertex_buffer.size())){

			//bump mapping
			float height = tex2D(bump, texCoord.x, texCoord.y);

			float dx = (tex2D(bump, tmp_texCoord.x+0.0005f, tmp_texCoord.y) - tex2D(bump, tmp_texCoord.x-0.0005f, tmp_texCoord.y))*1000.f;
			float dy = (tex2D(bump, tmp_texCoord.x, tmp_texCoord.y+0.0005f) - tex2D(bump, tmp_texCoord.x, tmp_texCoord.y-0.0005f))*1000.f;
			if(dx>0.f || dy >0.f){
				float3 o = normalize(-dx*tmp_tangent + dy*tmp_bitangent - sqrtf(dx*dx + dy*dy) * tmp_normal);
				float3 s = normalize(cross(tmp_normal, o));
				tmp_normal= normalize(cross(o,s));

			}

			//parallax mapping
			/*Matrix3x3 a;
			a.setCol(0, tmp_tangent);
			a.setCol(1, tmp_bitangent);
			a.setCol(2, tmp_normal);

			float3 eye_vec = (-current_ray.direction) * a;

			float parallax_limit = -length(make_float2(eye_vec))/eye_vec.z;
			parallax_limit*=BUMP_INTENSITY;

			float2 offSetDir=normalize(make_float2(eye_vec));
			float2 maxOffset = offSetDir * parallax_limit;

			int nSamples = (int) optix::lerp(1000.f, 500.f, dot(-current_ray.direction, tmp_normal));
			float step = 1.f/(float) nSamples;

			float ray_h = 1.f;
			float2 current_offset=make_float2(0.f);
			float2 last_offset=make_float2(0.f);

			float last_h=1.f;
			float current_h=1.f;

			int current_sample=0;

			while(current_sample<nSamples){
				current_h = tex2D(bump, tmp_texCoord.x + current_offset.x, tmp_texCoord.y - current_offset.y);
				if(current_h > ray_h){
					float delta1 = current_h - ray_h;
					float delta2 = (ray_h + step) - last_h;

					float ratio = delta1 / (delta1 + delta2);

					current_offset = ratio * last_offset + (1.f-ratio) * current_offset;

					current_sample = nSamples+1;
				}
				else{
					current_sample++;

					ray_h -= step;

					last_offset = current_offset;
					current_offset += step * maxOffset;

					last_h = current_h;
				}
			}

			tmp_texCoord.x += current_offset.x;
			tmp_texCoord.y -= current_offset.y;

			//t += current_h * dot(tmp_normal, -current_ray.direction);

			if(t< 0.1) return;

			float dx = (tex2D(bump, tmp_texCoord.x+0.0005f, tmp_texCoord.y) - tex2D(bump, tmp_texCoord.x-0.0005f, tmp_texCoord.y))*1000.f;
			float dy = (tex2D(bump, tmp_texCoord.x, tmp_texCoord.y+0.0005f) - tex2D(bump, tmp_texCoord.x, tmp_texCoord.y-0.0005f))*1000.f;
			if(dx>0.f || dy >0.f){
				float3 o = normalize(-dx*tmp_tangent + dy*tmp_bitangent - sqrtf(dx*dx + dy*dy) * tmp_normal);
				float3 s = normalize(cross(tmp_normal, o));
				tmp_normal= cross(o,s);

			}*/
		}

		if(rtPotentialIntersection(t))
		{

			//setting attributes
			shading_normal=tmp_normal;
			geometric_normal=optix::normalize(n);
			texCoord=tmp_texCoord;
			tangent=tmp_tangent;
			bitangent=tmp_bitangent;
			rtReportIntersection(0);
		}
	}
}

RT_PROGRAM void boundingBoxMesh(int primIdx, float result[6]){
    //get indices
    int3 id=index_buffer[primIdx];
    //load vertices
    float3 v1=vertex_buffer[id.x];
    float3 v2=vertex_buffer[id.y];
    float3 v3=vertex_buffer[id.z];

    /*float3 v1d=vertex_buffer[id.x]-normal_buffer[id.x]* 1.5f * BUMP_INTENSITY;
    float3 v2d=vertex_buffer[id.y]-normal_buffer[id.y]* 1.5f * BUMP_INTENSITY;
    float3 v3d=vertex_buffer[id.z]-normal_buffer[id.z]* 1.5f * BUMP_INTENSITY;*/
    const float area = optix::length(optix::cross(v2-v1,v3-v1));
    Aabb* aabb = (optix::Aabb*)result;
    if(area>0.0f)
    {
        /*aabb->m_min=fminf(fminf(fminf(v1, v1d),fminf(v2, v2d)), fminf(v3, v3d));
        aabb->m_max=fmaxf(fmaxf(fmaxf(v1, v1d),fmaxf(v2, v2d)), fmaxf(v3, v3d));*/

        aabb->m_min=fminf(fminf(v1,v2), v3);
        aabb->m_max=fmaxf(fmaxf(v1,v2), v3);
    }
    else
    {
        aabb->invalidate();
    }
}
