/*
 * commonStructs.h
 *
 *  Created on: 1 de Abr de 2014
 *      Author: cesar
 */

#ifndef COMMONSTRUCTS_H_
#define COMMONSTRUCTS_H_

#include <optix_world.h>

enum RayTypes{
	PathRay,
	ShadowRay,
	RAY_TYPE_COUNT
};

struct SphereLight{
	float4 pos;
	float4 color;
};

#endif /* COMMONSTRUCTS_H_ */
