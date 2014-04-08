/*
 * sphere_light_common.h
 *
 *  Created on: 8 de Abr de 2014
 *      Author: cesar
 */

#ifndef SPHERE_LIGHT_COMMON_H_
#define SPHERE_LIGHT_COMMON_H_

#include <optix_world.h>

struct SphereLight{
	optix::float4 pos;
	optix::float4 color;
};


#endif /* SPHERE_LIGHT_COMMON_H_ */
