#include "pch.h"
#include "raytracer.h"
#include "objloader.h"
#include "tutorials.h"
#include "mymath.h"
#include "omp.h"

Raytracer::Raytracer( const int width, const int height, const float fov_y, const Vector3 view_from, const Vector3 view_at) : SimpleGuiDX11( width, height )
{
	InitDeviceAndScene();
	camera = Camera(width, height, fov_y, view_from, view_at);
	fov = fov_y;
}

Raytracer::~Raytracer()
{
	ReleaseDeviceAndScene();
}

int Raytracer::InitDeviceAndScene()
{	
	error_handler(rtContextCreate(&context));
	error_handler(rtContextSetRayTypeCount(context, 1));
	error_handler(rtContextSetEntryPointCount(context, 1));
	error_handler(rtContextSetMaxTraceDepth(context, 10));

	RTvariable output;
	error_handler(rtContextDeclareVariable(context, "output_buffer", &output));
	error_handler(rtBufferCreate(context, RT_BUFFER_OUTPUT, &outputBuffer));
	error_handler(rtBufferSetFormat(outputBuffer, RT_FORMAT_UNSIGNED_BYTE4));
	error_handler(rtBufferSetSize2D(outputBuffer, width(), height()));
	error_handler(rtVariableSetObject(output, outputBuffer));

	RTprogram primary_ray;
	error_handler(rtProgramCreateFromPTXFile(context, "optixtutorial.ptx", "primary_ray", &primary_ray));
	error_handler(rtContextSetRayGenerationProgram(context, 0, primary_ray));
	error_handler(rtProgramValidate(primary_ray));

	rtProgramDeclareVariable(primary_ray, "focal_length",
		&focal_length);
	rtProgramDeclareVariable(primary_ray, "view_from",
		&view_from);
	rtProgramDeclareVariable(primary_ray, "M_c_w",
		&M_c_w);

	rtVariableSet3f(view_from, camera.view_from().x, camera.view_from().y, camera.view_from().z);
	rtVariableSet1f(focal_length, camera.focalLength());
	rtVariableSetMatrix3x3fv(M_c_w, 0, camera.M_c_w().data());

	RTprogram exception;
	error_handler(rtProgramCreateFromPTXFile(context, "optixtutorial.ptx", "exception", &exception));
	error_handler(rtContextSetExceptionProgram(context, 0, exception));
	error_handler(rtProgramValidate(exception));
	error_handler(rtContextSetExceptionEnabled(context, RT_EXCEPTION_ALL, 1));

	error_handler(rtContextSetPrintEnabled(context, 1));
	error_handler(rtContextSetPrintBufferSize(context, 4096));

	RTprogram miss_program;
	error_handler(rtProgramCreateFromPTXFile(context, "optixtutorial.ptx", "miss_program", &miss_program));
	error_handler(rtContextSetMissProgram(context, 0, miss_program));
	error_handler(rtProgramValidate(miss_program));

	return S_OK;
}

int Raytracer::ReleaseDeviceAndScene()
{
	error_handler(rtContextDestroy(context));
	return S_OK;
}

int Raytracer::initGraph() {
	error_handler(rtContextValidate(context));

	return S_OK;
}

int Raytracer::get_image(BYTE * buffer) {
	camera.updateFov(fov);
	camera.recalculateMcw();
	rtVariableSet3f(view_from, camera.view_from().x, camera.view_from().y, camera.view_from().z);
	rtVariableSet1f(focal_length, camera.focalLength());
	rtVariableSetMatrix3x3fv(M_c_w, 0, camera.M_c_w().data());

	error_handler(rtContextLaunch2D(context, 0, width(), height()));
	optix::uchar4 * data = nullptr;
	error_handler(rtBufferMap(outputBuffer, (void**)(&data)));
	memcpy(buffer, data, sizeof(optix::uchar4) * width() * height());
	error_handler(rtBufferUnmap(outputBuffer));
	return S_OK;
}

void Raytracer::LoadScene( const std::string file_name )
{
	const int no_surfaces = LoadOBJ( file_name.c_str(), surfaces_, materials_ );
	
	int no_triangles = 0;

	for (auto surface : surfaces_)
	{
		no_triangles += surface->no_triangles();
	}

	RTgeometrytriangles geometry_triangles;
	error_handler(rtGeometryTrianglesCreate(context, &geometry_triangles));
	error_handler(rtGeometryTrianglesSetPrimitiveCount(geometry_triangles, no_triangles));

	RTbuffer vertex_buffer;
	error_handler(rtBufferCreate(context, RT_BUFFER_INPUT, &vertex_buffer));
	error_handler(rtBufferSetFormat(vertex_buffer, RT_FORMAT_FLOAT3));
	error_handler(rtBufferSetSize1D(vertex_buffer, no_triangles * 3));
	
	RTvariable normals;
	rtContextDeclareVariable(context, "normal_buffer", &normals);
	RTbuffer normal_buffer;
	error_handler(rtBufferCreate(context, RT_BUFFER_INPUT, &normal_buffer));
	error_handler(rtBufferSetFormat(normal_buffer, RT_FORMAT_FLOAT3));
	error_handler(rtBufferSetSize1D(normal_buffer, no_triangles * 3));

	RTvariable materialIndices;
	rtContextDeclareVariable(context, "material_buffer", &materialIndices);
	RTbuffer material_buffer;
	error_handler(rtBufferCreate(context, RT_BUFFER_INPUT, &material_buffer));
	error_handler(rtBufferSetFormat(material_buffer, RT_FORMAT_UNSIGNED_BYTE));
	error_handler(rtBufferSetSize1D(material_buffer, no_triangles));

	optix::float3* vertexData = nullptr;
	optix::float3* normalData = nullptr;
	optix::uchar1* materialData = nullptr;

	error_handler(rtBufferMap(vertex_buffer, (void**)(&vertexData)));
	error_handler(rtBufferMap(normal_buffer, (void**)(&normalData)));
	error_handler(rtBufferMap(material_buffer, (void**)(&materialData)));

	// surfaces loop
	int k = 0, l = 0;
	for ( auto surface : surfaces_ )
	{		

		// triangles loop
		for (int i = 0; i < surface->no_triangles(); ++i, ++l )
		{
			Triangle & triangle = surface->get_triangle( i );

			materialData[l].x = (unsigned char)surface->get_material()->shader();

			// vertices loop
			for ( int j = 0; j < 3; ++j, ++k )
			{
				const Vertex & vertex = triangle.vertex(j);
				vertexData[k].x = vertex.position.x; 
				vertexData[k].y = vertex.position.y;
				vertexData[k].z = vertex.position.z;
				//printf("%d \n", k);
				normalData[k].x = vertex.normal.x;
				normalData[k].y = vertex.normal.y;
				normalData[k].z = vertex.normal.z;
			} // end of vertices loop

		} // end of triangles loop

	} // end of surfaces loop

	rtBufferUnmap(normal_buffer);
	rtBufferUnmap(material_buffer);
	rtBufferUnmap(vertex_buffer);

	rtBufferValidate(normal_buffer);
	rtVariableSetObject(normals, normal_buffer);

	rtBufferValidate(material_buffer);
	rtVariableSetObject(materialIndices, material_buffer);
	rtBufferValidate(vertex_buffer);

	error_handler(rtGeometryTrianglesSetMaterialCount(geometry_triangles, 2));
	error_handler(rtGeometryTrianglesSetMaterialIndices(geometry_triangles, material_buffer, 0, sizeof(optix::uchar1), RT_FORMAT_UNSIGNED_BYTE));
	error_handler(rtGeometryTrianglesSetVertices(geometry_triangles, no_triangles * 3, vertex_buffer, 0, sizeof(optix::float3), RT_FORMAT_FLOAT3));

	/*RTprogram attribute_program;
	error_handler(rtProgramCreateFromPTXFile(context, "optixtutorial.ptx", "attribute_program", &attribute_program));
	error_handler(rtProgramValidate(attribute_program));
	error_handler(rtGeometryTrianglesSetAttributeProgram(geometry_triangles, attribute_program));*/

	error_handler(rtGeometryTrianglesValidate(geometry_triangles));

	// material
	RTmaterial material;
	error_handler(rtMaterialCreate(context, &material));
	RTprogram closest_hit;
	error_handler(rtProgramCreateFromPTXFile(context, "optixtutorial.ptx", "closest_hit", &closest_hit));
	error_handler(rtProgramValidate(closest_hit));
	error_handler(rtMaterialSetClosestHitProgram(material, 0, closest_hit));
	//rtMaterialSetAnyHitProgram( material, 0, any_hit );	
	error_handler(rtMaterialValidate(material));

	// geometry instance
	RTgeometryinstance geometry_instance;
	error_handler(rtGeometryInstanceCreate(context, &geometry_instance));
	error_handler(rtGeometryInstanceSetGeometryTriangles(geometry_instance, geometry_triangles));
	error_handler(rtGeometryInstanceSetMaterialCount(geometry_instance, 2));
	error_handler(rtGeometryInstanceSetMaterial(geometry_instance, 0, material));
	error_handler(rtGeometryInstanceSetMaterial(geometry_instance, 1, material));
	error_handler(rtGeometryInstanceValidate(geometry_instance));

	// acceleration structure
	RTacceleration sbvh;
	error_handler(rtAccelerationCreate(context, &sbvh));
	error_handler(rtAccelerationSetBuilder(sbvh, "Sbvh"));
	//error_handler( rtAccelerationSetProperty( sbvh, "vertex_buffer_name", "vertex_buffer" ) );
	error_handler(rtAccelerationValidate(sbvh));

	// geometry group
	RTgeometrygroup geometry_group;
	error_handler(rtGeometryGroupCreate(context, &geometry_group));
	error_handler(rtGeometryGroupSetAcceleration(geometry_group, sbvh));
	error_handler(rtGeometryGroupSetChildCount(geometry_group, 1));
	error_handler(rtGeometryGroupSetChild(geometry_group, 0, geometry_instance));
	error_handler(rtGeometryGroupValidate(geometry_group));

	RTvariable top_object;
	error_handler(rtContextDeclareVariable(context, "top_object", &top_object));
	error_handler(rtVariableSetObject(top_object, geometry_group));
}

int Raytracer::Ui()
{
	static float f = 0.0f;
	static int counter = 0;

	ImGui::Begin( "Ray Tracer Params" );
	
	ImGui::Text( "Surfaces = %d", surfaces_.size() );
	ImGui::Text( "Materials = %d", materials_.size() );
	ImGui::Separator();
	ImGui::Checkbox( "Vsync", &vsync_ );
	ImGui::Checkbox( "Unify normals", &unify_normals_ );	

	ImGui::SliderFloat( "gamma", &gamma_, 0.1f, 5.0f );
	ImGui::SliderFloat("fov", &fov, 0.1f, 5.0f);
	ImGui::SliderFloat("Mouse sensitivity", &mouseSensitivity, 0.1f, 100.0f);
	ImGui::SliderInt("'Speed", &speed, 0, 10);

	bool arrowUpPressed = GetKeyState(VK_UP) & 0x8000 ? true : false;
	bool arrowDownPressed = GetKeyState(VK_DOWN) & 0x8000 ? true : false;
	bool arrowLeftPressed = GetKeyState(VK_LEFT) & 0x8000 ? true : false;
	bool arrowRightPressed = GetKeyState(VK_RIGHT) & 0x8000 ? true : false;
	bool wPressed = GetKeyState('W') & 0x8000 ? true : false;
	bool aPressed = GetKeyState('A') & 0x8000 ? true : false;
	bool sPressed = GetKeyState('S') & 0x8000 ? true : false;
	bool dPressed = GetKeyState('D') & 0x8000 ? true : false;
	bool zPressed = GetKeyState('Z') & 0x8000 ? true : false;
	bool cPressed = GetKeyState('C') & 0x8000 ? true : false;

	float time = ImGui::GetIO().DeltaTime * 60;

	double frameStep = speed * time;

	if (arrowUpPressed) camera.moveForward(frameStep);
	if (arrowDownPressed) camera.moveForward(-frameStep);
	if (arrowRightPressed) camera.moveRight(frameStep);
	if (arrowLeftPressed) camera.moveRight(-frameStep);
	if (dPressed) camera.rotateRight(frameStep);
	if (aPressed) camera.rotateRight(-frameStep);
	if (sPressed) camera.rotateUp(frameStep);
	if (wPressed) camera.rotateUp(-frameStep);
	if (cPressed) camera.rollRight(frameStep);
	if (zPressed) camera.rollRight(-frameStep);

	ImGui::Text( "Application average %.3f ms/frame (%.1f FPS)", 1000.0f / ImGui::GetIO().Framerate, ImGui::GetIO().Framerate );
	ImGui::End();
	return 0;
}
