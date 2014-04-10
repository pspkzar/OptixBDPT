#include <optix_world.h>
#include "mesh.h"

#define BUMP_INTENSITY 0.5f

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
			float height = tex2D(bump, texCoord.x, texCoord.y);
			float ray_n = dot(current_ray.direction, tmp_normal);

			float dx = tex2D(bump, tmp_texCoord.x+0.0001, tmp_texCoord.y) - tex2D(bump, tmp_texCoord.x-0.0001, tmp_texCoord.y);
			float dy = tex2D(bump, tmp_texCoord.x, tmp_texCoord.y+0.0001) - tex2D(bump, tmp_texCoord.x, tmp_texCoord.y-0.0001);

			tmp_normal=normalize(tmp_normal+ 10000.f * (-dx*tmp_tangent + dy * tmp_bitangent));
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
