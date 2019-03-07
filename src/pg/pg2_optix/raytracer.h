#pragma once
#include "simpleguidx11.h"
#include "surface.h"

/*! \class Raytracer
\brief General ray tracer class.

\author Tomáš Fabián
\version 0.1
\date 2018
*/
class Raytracer : public SimpleGuiDX11
{
public:
	Raytracer( const int width, const int height );
	~Raytracer();

	int InitDeviceAndScene();
	int initGraph();
	int get_image(BYTE * buffer) override;
	int ReleaseDeviceAndScene();

	void LoadScene( const std::string file_name );

	//Color3f get_pixel( const int x, const int y, const float t = 0.0f ) override;		

	int Ui();

private:	
	std::vector<Surface *> surfaces_;
	std::vector<Material *> materials_;			
	
	RTcontext context = {0};
	RTbuffer outputBuffer = { 0 };


	bool unify_normals_{ true };
};
