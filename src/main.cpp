#include <optix_world.h>
#include <optixu/optixpp_namespace.h>
#include "commonStructs.h"
#include "OptixContext.h"


#include <GL/glew.h>
#include <GL/freeglut.h>

using namespace optix;
using namespace std;

int w = 200, h=200;
Context optix_context;

void reshape(int nw, int nh){
	//TODO reshape buffer and dimensions
}

void renderScene(){
	optix_context->launch(0, w, h);
	Buffer output = optix_context["output"]->getBuffer();
	void *pixels=output->map();
	glDrawPixels(w, h, GL_RGBA, GL_FLAT, pixels);
	output->unmap();
	//TODO update frame number
	glutSwapBuffers();
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

	Program camera = oc->createProgramFromPTXFile(app_loc+"path.ptx", "camera");
	Program exception = oc->createProgramFromPTXFile(app_loc+"path.ptx", "exception");
	oc->setEntryPointCount(1);
	oc->setRayGenerationProgram(0, camera);
	oc->setExceptionProgram(0, exception);

	//TODO set lights and camera variables


	oc->setStackSize(5000);
	oc->setPrintEnabled(true);

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
	//glutKeyboardFunc(keyboard);
	glutIdleFunc(renderScene);
	return 0;
}
