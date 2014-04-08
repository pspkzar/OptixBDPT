#include <optix_world.h>
#include "mesh.h"

rtDeclareVariable(float, t_hit, rtIntersectionDistance, );
rtDeclareVariable(optix::Ray, current_ray, rtCurrentRay, );

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
	if(optix::intersect_triangle(current_ray, v1, v2, v3, n, t, beta, gamma))
	{
		if(rtPotentialIntersection(t))
		{
			//loading normals
			float3 n1=normal_buffer[id.x];
			float3 n2=normal_buffer[id.y];
			float3 n3=normal_buffer[id.z];

			if(tangent_buffer.size()==vertex_buffer.size()){
				float3 t1=tangent_buffer[id.x];
				float3 t2=tangent_buffer[id.y];
				float3 t3=tangent_buffer[id.z];

				float3 b1=bitangent_buffer[id.x];
				float3 b2=bitangent_buffer[id.y];
				float3 b3=bitangent_buffer[id.z];

				tangent=(1.0f-beta-gamma)*t1 + beta*t2 +gamma*t3;
				bitangent=(1.0f-beta-gamma)*b1 + beta*b2 +gamma*b3;
			}
			else{
				tangent=make_float3(0.f);
				bitangent=make_float3(0.f);
			}


			//loading texCoords
			if(texCoord_buffer.size()==vertex_buffer.size()){
				float2 t1=texCoord_buffer[id.x];
				float2 t2=texCoord_buffer[id.y];
				float2 t3=texCoord_buffer[id.z];
				texCoord=(1.0f-beta-gamma)*t1 + beta*t2 +gamma*t3;
			}
			else
			{
				texCoord=make_float2(1.0f,0.0f);
			}
			//setting attributes
			shading_normal=(1.0f-beta-gamma)*n1 + beta*n2 +gamma*n3;
			geometric_normal=optix::normalize(n);
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
    const float area = optix::length(optix::cross(v2-v1,v3-v1));
    optix::Aabb* aabb = (optix::Aabb*)result;
    if(area>0.0f)
    {
        aabb->m_min=fminf(fminf(v1,v2),v3);
        aabb->m_max=fmaxf(fmaxf(v1,v2),v3);
    }
    else
    {
        aabb->invalidate();
    }
}
