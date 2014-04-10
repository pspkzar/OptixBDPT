#include <optix_world.h>
#include <optixu/optixpp_namespace.h>
#include "commonStructs.h"
#include "OptixContext.h"
#include "SphereLightLoader.h"

#include <GL/glew.h>
#include <GL/freeglut.h>

#define STEP 2.f
#define ANG_STEP 0.1f

using namespace optix;
using namespace std;

int w = 800, h=800;
int frame=1;
Context optix_context;

float3 eye=make_float3(0.f, 0.f, 0.f);
float3 up=make_float3(0.f,1.f,0.f);
float3 W=make_float3(0.f, 0.f, -1.f);


void reshape(int nw, int nh){
	w=nw;
	h=nh;
	glViewport(0, 0, w, h);
	Buffer output = optix_context["output"]->getBuffer();
	output->setSize(w, h);
	frame=1;
	optix_context["frame"]->setInt(frame);
}

void renderScene(){
	glClear(GL_COLOR_BUFFER_BIT);
	optix_context->launch(0, w, h);
	Buffer output = optix_context["output"]->getBuffer();
	void *pixels=output->map();
	glDrawPixels(w, h, GL_RGBA, GL_FLOAT, pixels);
	output->unmap();
	optix_context["frame"]->setInt(++frame);
	glutSwapBuffers();
}

void keyboard(unsigned char key, int x, int y){

    float3 U=normalize(cross(up,-W));
    float3 V=cross(-W, U);

    switch(key){
    case 'w':
        eye+=STEP*W;
        break;
    case 's':
        eye-=STEP*W;
        break;

    case 'i':
        W=normalize(W+ANG_STEP*V);
        break;
    case 'k':
        W=normalize(W-ANG_STEP*V);
        break;

    case 'l':
        W=normalize(W+ANG_STEP*U);
        break;
    case 'j':
        W=normalize(W-ANG_STEP*U);
        break;
    }

    U=normalize(cross(up,-W));
    V=cross(-W, U);

    optix_context["eye"]->setFloat(eye);
    optix_context["U"]->setFloat(U);
    optix_context["V"]->setFloat(V);
    optix_context["W"]->setFloat(W);

    frame=1;
    optix_context["frame"]->setInt(frame);
}

int main(int argc, char **argv){

	string command(argv[0]);
	string app_loc;
	int slash_i=command.find_last_of("\\/");
	if(slash_i==command.npos){
		app_loc="";
	}
	else{
		app_loc=command.substr(0, slash_i+1);
	}

	OptixContext c("crytek-sponza/sponza.obj");
	c.setBoundingBoxProgram(app_loc+"mesh.ptx", "boundingBoxMesh");
	c.setIntersectionProgram(app_loc+"mesh.ptx", "intersectMesh");

	c.setRayTypeCount(RAY_TYPE_COUNT);

	c.setClosestHitProgram(PathRay, app_loc+"path.ptx", "glossy_shading");
	c.setAnyHitProgram(PathRay, app_loc+"path.ptx", "path_ignore_alpha");

	c.setAnyHitProgram(ShadowRay, app_loc+"path.ptx", "shadow_probe");

	Context oc = c.getContext();

	Program path_miss = oc->createProgramFromPTXFile(app_loc+"path.ptx", "path_miss");
	oc->setMissProgram(PathRay, path_miss);

	SphereLight lights[1];
	lights[0].color=make_float4(400.f);
	lights[0].pos=make_float4(0.f, 5350.f, 0.f, 1050.f);

	SphereLightLoader l_loader(lights, 1, oc);
	l_loader.light_geom->setBoundingBoxProgram(oc->createProgramFromPTXFile(app_loc+"sphere_light.ptx", "sphere_light_bounding_box"));
	l_loader.light_geom->setIntersectionProgram(oc->createProgramFromPTXFile(app_loc+"sphere_light.ptx", "sphere_light_intersect"));

	l_loader.light_mat->setClosestHitProgram(PathRay, oc->createProgramFromPTXFile(app_loc+"path.ptx", "light_shading" ));

	l_loader.light_mat->setAnyHitProgram(ShadowRay, oc->createProgramFromPTXFile(app_loc+"path.ptx", "shadow_probe_light" ));

	Program camera = oc->createProgramFromPTXFile(app_loc+"path.ptx", "camera");
	Program exception = oc->createProgramFromPTXFile(app_loc+"path.ptx", "exception");
	oc->setEntryPointCount(1);
	oc->setRayGenerationProgram(0, camera);
	oc->setExceptionProgram(0, exception);

	oc["frame"]->setInt(frame);

	Buffer output = oc->createBuffer(RT_BUFFER_OUTPUT, RT_FORMAT_FLOAT4, w, h);
	oc["output"]->set(output);

	//TODO set camera variables
	oc["eye"]->setFloat(eye);
	oc["U"]->setFloat(normalize(cross(-W, up)));
	oc["V"]->setFloat(up);
	oc["W"]->setFloat(W);

	oc->setStackSize(4000);
	oc->setPrintEnabled(true);

	Group g = oc->createGroup();
	g->setChildCount(2);
	g->setChild(0, c.getMeshes());
	g->setChild(1, l_loader.light_group);
	g->setAcceleration(oc->createAcceleration("NoAccel","NoAccel"));

	oc["top_object"]->set(g);

	oc->validate();

	optix_context=oc;

	//init glut
	glutInit(&argc, argv);
	glutInitDisplayMode(GLUT_RGBA|GLUT_DOUBLE);
	glutInitWindowPosition(0,0);
	glutInitWindowSize(w,h);
	glutCreateWindow("Optix BDPT");
	//init glew
	glewInit();
	//callbacks
	glutReshapeFunc(reshape);
	glutDisplayFunc(renderScene);
	//TODO keyboard and mouse funcions to allow interactivity
	glutKeyboardFunc(keyboard);
	glutIdleFunc(renderScene);

	glutMainLoop();
	return 0;
}
