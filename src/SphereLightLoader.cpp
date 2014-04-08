/*
 * SphereLightLoader.cpp
 *
 *  Created on: 8 de Abr de 2014
 *      Author: cesar
 */

#include "SphereLightLoader.h"

using namespace optix;

SphereLightLoader::SphereLightLoader(SphereLight * lights, int nlights, Context c) {
	Buffer b = c->createBuffer(RT_BUFFER_INPUT, RT_FORMAT_USER);
	b->setElementSize(sizeof(SphereLight));
	b->setSize(nlights);
	SphereLight * tmp_lights = static_cast<SphereLight *>(b->map());

	for(int i=0; i<nlights; i++){
		tmp_lights[i]=lights[i];
	}

	b->unmap();

	c["lights"]->set(b);

	light_geom = c->createGeometry();
	light_geom->setPrimitiveCount(nlights);

	light_mat = c->createMaterial();

	GeometryInstance instance = c->createGeometryInstance();
	instance->setMaterialCount(1);
	instance->setMaterial(0, light_mat);
	instance->setGeometry(light_geom);

	light_group = c->createGeometryGroup();
	light_group->setAcceleration(c->createAcceleration("NoAccel", "NoAccel"));
	light_group->setChildCount(1);
	light_group->setChild(0, instance);
}

SphereLightLoader::~SphereLightLoader() {
	// TODO Auto-generated destructor stub
}

