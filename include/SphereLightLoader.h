/*
 * SphereLightLoader.h
 *
 *  Created on: 8 de Abr de 2014
 *      Author: cesar
 */

#ifndef SPHERELIGHTLOADER_H_
#define SPHERELIGHTLOADER_H_

#include <optix_world.h>
#include <optixu/optixpp_namespace.h>
#include "sphere_light_common.h"

class SphereLightLoader {
public:
	SphereLightLoader(SphereLight * lights, int nlights, optix::Context c);
	virtual ~SphereLightLoader();

	optix::Geometry light_geom;
	optix::Material light_mat;
	optix::GeometryGroup light_group;
};

#endif /* SPHERELIGHTLOADER_H_ */
