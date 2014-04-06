#ifndef MESH_H_
#define MESH_H_

#include <optix_world.h>
#include "attributes.h"

rtBuffer<int3>index_buffer;
rtBuffer<float3>vertex_buffer;
rtBuffer<float3>normal_buffer;

rtBuffer<float2>texCoord_buffer;

rtBuffer<float3>tangent_buffer;
rtBuffer<float3>bitangent_buffer;


#endif /* MESH_H_ */
