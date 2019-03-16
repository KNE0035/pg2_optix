#include "optixtutorial.h"

struct TriangleAttributes
{
	optix::float3 normal;
	optix::float2 texcoord;
};

rtBuffer<optix::float3, 1> normal_buffer;
rtBuffer<optix::float2, 1> texcoord_buffer;
rtBuffer<optix::uchar4, 2> output_buffer;

rtDeclareVariable( optix::float3, diffuse, , "diffuse" );rtDeclareVariable(int, tex_diffuse_id, , "diffuse texture id");

rtDeclareVariable( rtObject, top_object, , );
rtDeclareVariable( uint2, launch_dim, rtLaunchDim, );
rtDeclareVariable( uint2, launch_index, rtLaunchIndex, );
rtDeclareVariable( PerRayData_radiance, ray_data, rtPayload, );
rtDeclareVariable( PerRayData_shadow, shadow_ray_data, rtPayload, );
rtDeclareVariable( float2, barycentrics, attribute rtTriangleBarycentrics, );
rtDeclareVariable(optix::Ray, ray, rtCurrentRay, );
rtDeclareVariable(TriangleAttributes, attribs, attribute attributes, "Triangle attributes");
rtDeclareVariable(optix::float3, view_from, , );
rtDeclareVariable(optix::Matrix3x3, M_c_w, , "camera to worldspace transformation matrix" );
rtDeclareVariable(float, focal_length, , "focal length in pixels" );


RT_PROGRAM void attribute_program( void )
{
	const optix::float2 barycentrics = rtGetTriangleBarycentrics();
	const unsigned int index = rtGetPrimitiveIndex();
	const optix::float3 n0 = normal_buffer[index * 3 + 0];
	const optix::float3 n1 = normal_buffer[index * 3 + 1];
	const optix::float3 n2 = normal_buffer[index * 3 + 2];

	const optix::float2 t0 = texcoord_buffer[index * 3 + 0];
	const optix::float2 t1 = texcoord_buffer[index * 3 + 1];
	const optix::float2 t2 = texcoord_buffer[index * 3 + 2];

	attribs.normal = optix::normalize(n1 * barycentrics.x + n2 * barycentrics.y + n0 * (1.0f - barycentrics.x - barycentrics.y));
	attribs.texcoord = t1 * barycentrics.x + t2 * barycentrics.y + t0 * (1.0f - barycentrics.x - barycentrics.y);

	if (optix::dot(ray.direction, attribs.normal) > 0) {
		attribs.normal *= -1;
	}
}

RT_PROGRAM void primary_ray( void )
{
	PerRayData_radiance prd;
	curandState_t state;
	prd.state = &state;
	curand_init(launch_index.x + launch_dim.x * launch_index.y, 0, 0, prd.state);

	int ANTI_ALIASING_SAMPLES = 8;
	int NO_SAMPLES = 30;

	optix::float3 resultColor = optix::make_float3(0.0f, 0.0f, 0.0f);
	for (int i = 0; i < ANTI_ALIASING_SAMPLES; i++)
	{
		float randomX = curand_uniform(prd.state);
		float randomY = curand_uniform(prd.state);

		const optix::float3 d_c = make_float3(launch_index.x - launch_dim.x * 0.5f + randomX, 
											  output_buffer.size().y * 0.5f - launch_index.y + randomY, 
											  -focal_length);

		const optix::float3 d_w = optix::normalize(M_c_w * d_c);
		optix::Ray ray(view_from, d_w, 0, 0.01f);

		for (int j = 0; j < NO_SAMPLES; j++) {
			rtTrace(top_object, ray, prd);
			resultColor += prd.result;
		}
	}
	resultColor /= ANTI_ALIASING_SAMPLES;
	output_buffer[launch_index] = optix::make_uchar4(resultColor.x*255.0f, resultColor.y*255.0f, resultColor.z*255.0f, 255 );
}

RT_PROGRAM void closest_hit_normal_shader( void )
{
	optix::float3 normal = attribs.normal;
	ray_data.result = optix::make_float3((normal.x + 1) / 2, (normal.y + 1) / 2, (normal.z + 1) / 2);
}

enum class Shader : char { NORMAL = 1, LAMBERT = 2, PHONG = 3, GLASS = 4, PBR = 5, MIRROR = 6, TS = 7, CT = 8 };

RT_PROGRAM void closest_hit_lambert_shader(void)
{
	ray_data.depth++;
	//printf("%d \n", ray_data.depth);
	//printf("%d \n", ray.ray_type);
	optix::float3 lightPossition = optix::make_float3(7, 0, 120);
	
	optix::float3 intersectionPoint = optix::make_float3(ray.origin.x + ray.tmax * ray.direction.x, 
														ray.origin.y + ray.tmax * ray.direction.y,
														ray.origin.z + ray.tmax * ray.direction.z);

	optix::float3 vectorToLight = optix::normalize(lightPossition - intersectionPoint);
	optix::float3 normal = attribs.normal;

	float normalLigthScalarProduct = optix::dot(vectorToLight, normal);
	
	float pdf = 0;
	optix::float3 omegai = sampleHemisphere(normal, ray_data.state, pdf);
	
	optix::Ray ray(intersectionPoint, omegai, 1, 0.01f);
	PerRayData_shadow shadow_ray;
	shadow_ray.visible.x = 1;
	rtTrace(top_object, ray, shadow_ray);

	optix::float3 color;

	if (tex_diffuse_id != -1) {
		const optix::float4 value = optix::rtTex2D<optix::float4>(tex_diffuse_id, attribs.texcoord.x, 1 - attribs.texcoord.y);
		color = optix::make_float3(value.x, value.y, value.z);
	}
	else {
		color = optix::make_float3(diffuse.x, diffuse.y, diffuse.z);
	}

	ray_data.result = color * (normalLigthScalarProduct * optix::dot(normal, omegai) * shadow_ray.visible.x * (1 / CUDART_PI_F * pdf));
}

RT_PROGRAM void closest_hit_phong_shader(void)
{
}

RT_PROGRAM void closest_hit_glass_shader(void)
{
}

RT_PROGRAM void closest_hit_pbr_shader(void)
{
}

RT_PROGRAM void closest_hit_mirror_shader(void)
{
}

RT_PROGRAM void any_hit(void)
{
	//if (diffuse.x == 1.0) {
		shadow_ray_data.visible.x = 0;
	//}
	//else {
	//	shadow_ray_data.visible.x = 0;
	//}
	rtTerminateRay();
}


/* may access variables declared with the rtPayload semantic in the same way as closest-hit and any-hit programs */
RT_PROGRAM void miss_program( void )
{
	ray_data.result = optix::make_float3( 0.0f, 0.0f, 0.0f );
}

RT_PROGRAM void exception( void )
{
	const unsigned int code = rtGetExceptionCode();
	rtPrintf( "Exception 0x%X at (%d, %d)\n", code, launch_index.x, launch_index.y );
	rtPrintExceptionDetails();
	output_buffer[launch_index] = uchar4{ 255, 0, 255, 0 };
}__device__ optix::float3 sampleHemisphere(optix::float3 normal, curandState_t* state, float& pdf) {
	float randomU = curand_uniform(state);	
	float randomV = curand_uniform(state);

	float x = 2 * cosf(2 * CUDART_PI_F * randomU) * sqrtf(randomV * (1 - randomV));
	float y = 2 * sinf(2 * CUDART_PI_F * randomU) * sqrtf(randomV * (1 - randomV));
	float z = 1 - 2 * randomV;

	optix::float3 omegai = optix::make_float3(x, y , z);

	if (optix::dot(normal, omegai) < 0) 
	{
		omegai *= -1;
	}

	pdf = 1 / (2 * CUDART_PI_F);
	return omegai;}