/*
 * optix_context.h
 *
 *  Created on: 1 de Abr de 2014
 *      Author: cesar
 */

#ifndef OPTIX_CONTEXT_H_
#define OPTIX_CONTEXT_H_

#include <optix_world.h>
#include "random.h"

#include "commonStructs.h"

// Intersection attributes
rtDeclareVariable(float3, pos, attribute pos, );
rtDeclareVariable(float3, geometric_normal, attribute geometric_normal, );
rtDeclareVariable(float3, shading_normal, attribute shading_normal, );
rtDeclareVariable(float, t_hit, rtIntersectionDistance, );
//rtDeclareVariable(float3, tangent, attribute tangent, );
//rtDeclareVariable(float3, bitangent, attribute bitangent, );

rtBuffer<SphereLight> lights;

#endif /* OPTIX_CONTEXT_H_ */
