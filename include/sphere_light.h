/*
 * sphere_light.h
 *
 *  Created on: 8 de Abr de 2014
 *      Author: cesar
 */

#ifndef SPHERE_LIGHT_H_
#define SPHERE_LIGHT_H_

#include <optix_world.h>

#include "sphere_light_common.h"

rtBuffer<SphereLight> lights;

rtDeclareVariable(SphereLight, light, attribute light, );


#endif /* SPHERE_LIGHT_H_ */
