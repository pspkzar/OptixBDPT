#ifndef OPTIX_CONTEXT_H_
#define OPTIX_CONTEXT_H_

#include <optix_world.h>

// Intersection attributes
//rtDeclareVariable(float3, pos, attribute pos, );
rtDeclareVariable(float3, geometric_normal, attribute geometric_normal, );
rtDeclareVariable(float3, shading_normal, attribute shading_normal, );
rtDeclareVariable(float2, texCoord, attribute texCoord, );
rtDeclareVariable(float3, tangent, attribute tangent, );
rtDeclareVariable(float3, bitangent, attribute bitangent, );



#endif /* OPTIX_CONTEXT_H_ */
