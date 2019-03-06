#include "optixtutorial.h"

rtBuffer<uchar4, 2> output_buffer;

rtDeclareVariable( rtObject, top_object, , );
rtDeclareVariable( uint2, launch_dim, rtLaunchDim, );
rtDeclareVariable( uint2, launch_index, rtLaunchIndex, );
rtDeclareVariable( PerRayData_radiance, ray_data, rtPayload, );
rtDeclareVariable( float2, barycentrics, attribute rtTriangleBarycentrics, );

RT_PROGRAM void primary_ray( void )
{
	if ( launch_index.x == 0 && launch_index.y % 100 == 0 )
	{
		rtPrintf( "(%u, %u)\n", launch_index.x, launch_index.y );	
	}	

	optix::Ray ray( optix::make_float3( launch_index.x, launch_index.y, 1.0f ),
		optix::normalize( optix::make_float3( 0.0f, 0.0f, -1.0f ) ), 0, 0.01f );
	PerRayData_radiance prd;
	rtTrace( top_object, ray, prd );

	// access to buffers within OptiX programs uses a simple array syntax	
	output_buffer[launch_index] = optix::make_uchar4( prd.result.x*255.0f, prd.result.y*255.0f, prd.result.z*255.0f, 255 );
}

RT_PROGRAM void closest_hit( void )
{
	ray_data.result = optix::make_float3( barycentrics.x, barycentrics.y, 0.0f );
}

/* may access variables declared with the rtPayload semantic in the same way as closest-hit and any-hit programs */
RT_PROGRAM void miss_program( void )
{
	ray_data.result = optix::make_float3( 0.0f, 0.0f, 1.0f );
}

RT_PROGRAM void exception( void )
{
	const unsigned int code = rtGetExceptionCode();
	rtPrintf( "Exception 0x%X at (%d, %d)\n", code, launch_index.x, launch_index.y );
	rtPrintExceptionDetails();
	output_buffer[launch_index] = uchar4{ 255, 0, 255, 0 };
}
