#include "optixtutorial.h"

struct IntersectionInfo
{
	optix::float3 normal;
	optix::float2 texcoord;
	optix::float3 intersectionPoint;
	optix::float3 vectorToLight;
};

rtBuffer<optix::float3, 1> normal_buffer;
rtBuffer<optix::float2, 1> texcoord_buffer;
rtBuffer<optix::uchar4, 2> output_buffer;

rtDeclareVariable( optix::float3, diffuse, , "diffuse" );rtDeclareVariable(optix::float3, specular, , "specular");rtDeclareVariable(optix::float3, ambient, , "ambient");rtDeclareVariable(float, shininess, , "shininess");rtDeclareVariable(int, tex_diffuse_id, , "diffuse texture id");

rtDeclareVariable( rtObject, top_object, , );
rtDeclareVariable( uint2, launch_dim, rtLaunchDim, );
rtDeclareVariable( uint2, launch_index, rtLaunchIndex, );
rtDeclareVariable( PerRayData_radiance, ray_data, rtPayload, );
rtDeclareVariable( PerRayData_shadow, shadow_ray_data, rtPayload, );
rtDeclareVariable( float2, barycentrics, attribute rtTriangleBarycentrics, );
rtDeclareVariable(optix::Ray, ray, rtCurrentRay, );
rtDeclareVariable(IntersectionInfo, hitInfo, attribute attributes, "Intersection info");
rtDeclareVariable(optix::float3, view_from, , );
rtDeclareVariable(optix::Matrix3x3, M_c_w, , "camera to worldspace transformation matrix" );
rtDeclareVariable(float, focal_length, , "focal length in pixels" );


RT_PROGRAM void attribute_program( void )
{
	const optix::float3 lightPossition = optix::make_float3(50, 0, 120);
	const optix::float2 barycentrics = rtGetTriangleBarycentrics();
	const unsigned int index = rtGetPrimitiveIndex();
	const optix::float3 n0 = normal_buffer[index * 3 + 0];
	const optix::float3 n1 = normal_buffer[index * 3 + 1];
	const optix::float3 n2 = normal_buffer[index * 3 + 2];

	const optix::float2 t0 = texcoord_buffer[index * 3 + 0];
	const optix::float2 t1 = texcoord_buffer[index * 3 + 1];
	const optix::float2 t2 = texcoord_buffer[index * 3 + 2];

	hitInfo.normal = optix::normalize(n1 * barycentrics.x + n2 * barycentrics.y + n0 * (1.0f - barycentrics.x - barycentrics.y));
	hitInfo.texcoord = t1 * barycentrics.x + t2 * barycentrics.y + t0 * (1.0f - barycentrics.x - barycentrics.y);

	if (optix::dot(ray.direction, hitInfo.normal) > 0) {
		hitInfo.normal *= -1;
	}

	hitInfo.intersectionPoint = optix::make_float3(ray.origin.x + ray.tmax * ray.direction.x,
									ray.origin.y + ray.tmax * ray.direction.y,
									ray.origin.z + ray.tmax * ray.direction.z);

	hitInfo.vectorToLight = optix::normalize(lightPossition - hitInfo.intersectionPoint);
}

RT_PROGRAM void primary_ray( void )
{
	PerRayData_radiance prd;
	curandState_t state;
	prd.state = &state;
	curand_init(launch_index.x + launch_dim.x * launch_index.y, 0, 0, prd.state);
	int ANTI_ALIASING_SAMPLES = 8;
	int NO_SAMPLES = 64;

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

		optix::float3 ambientColor = optix::make_float3(0.0f, 0.0f, 0.0f);
		for (int j = 0; j < NO_SAMPLES; j++) {
			rtTrace(top_object, ray, prd);
			ambientColor += prd.result;
		}
		ambientColor /= NO_SAMPLES;
		resultColor += ambientColor;
	}
	resultColor /=  ANTI_ALIASING_SAMPLES;
	output_buffer[launch_index] = optix::make_uchar4(resultColor.x*255.0f, resultColor.y*255.0f, resultColor.z*255.0f, 255 );
}

RT_PROGRAM void closest_hit_normal_shader( void )
{
	optix::float3 normal = hitInfo.normal;
	ray_data.result = optix::make_float3((normal.x + 1) / 2, (normal.y + 1) / 2, (normal.z + 1) / 2);
}

enum class Shader : char { NORMAL = 1, LAMBERT = 2, PHONG = 3, GLASS = 4, PBR = 5, MIRROR = 6, TS = 7, CT = 8 };

RT_PROGRAM void closest_hit_lambert_shader(void)
{
	float normalLigthScalarProduct = optix::dot(hitInfo.vectorToLight, hitInfo.normal);
	ray_data.result = getDiffuseColor() * normalLigthScalarProduct * getAmbientColor();
}

RT_PROGRAM void closest_hit_phong_shader(void)
{
	float normalLigthScalarProduct = optix::dot(hitInfo.vectorToLight, hitInfo.normal);
	float normalViewScalarProduct = optix::dot(hitInfo.normal, ray.direction);

	optix::float3 lr = 2 * (normalLigthScalarProduct)* hitInfo.normal - hitInfo.vectorToLight;
	
	ray_data.result.x = ambient.x + (getDiffuseColor().x * normalLigthScalarProduct) + specular.x * pow(optix::dot(-ray.direction, lr), shininess);
	ray_data.result.y = ambient.y + (getDiffuseColor().y * normalLigthScalarProduct) + specular.y * pow(optix::dot(-ray.direction, lr), shininess);
	ray_data.result.z = ambient.z + (getDiffuseColor().z * normalLigthScalarProduct) + specular.z * pow(optix::dot(-ray.direction, lr), shininess);

	ray_data.result = ray_data.result * getAmbientColor();
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
	shadow_ray_data.visible.x = 0;
	rtTerminateRay();
}

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

	float x = cosf(2 * CUDART_PI_F * randomU) * sqrtf(1 - randomV);
	float y = sinf(2 * CUDART_PI_F * randomU) * sqrtf(1 - randomV);
	float z = sqrtf(randomV);

	optix::float3 O1 = optix::normalize(orthogonal(normal));
	optix::float3 O2 = optix::normalize(optix::cross(normal, O1));

	optix::Matrix3x3 transformationMatrix = optix::make_matrix3x3(optix::Matrix<4, 4>::fromBasis(O1, O2, normal, optix::make_float3(0.0f, 0.0f, 0.0f) ));

	optix::float3 omegai = optix::make_float3(x, y, z);

	omegai = optix::normalize(transformationMatrix * omegai);

	pdf = optix::dot(normal, omegai) / CUDART_PI_F;

	return omegai;}__device__ optix::float3 orthogonal(const optix::float3 & v)
{
	return (abs(v.x) > abs(v.z)) ? optix::make_float3(-v.y, v.x, 0.0f) : optix::make_float3(0.0f, -v.z, v.y);
}

__device__ optix::float3 getAmbientColor()
{
	float pdf = 0;
	optix::float3 omegai = sampleHemisphere(hitInfo.normal, ray_data.state, pdf);

	optix::Ray ray(hitInfo.intersectionPoint, omegai, 1, 0.01f);
	PerRayData_shadow shadow_ray;
	shadow_ray.visible.x = 1;
	rtTrace(top_object, ray, shadow_ray);

	optix::float3 whiteColor = optix::make_float3(1, 1, 1);
	return whiteColor * optix::dot(hitInfo.normal, omegai) * shadow_ray.visible.x / CUDART_PI_F / pdf;
}

__device__ optix::float3 getDiffuseColor()
{
	optix::float3 color;
	if (tex_diffuse_id != -1) {
		const optix::float4 value = optix::rtTex2D<optix::float4>(tex_diffuse_id, hitInfo.texcoord.x, 1 - hitInfo.texcoord.y);
		color = optix::make_float3(value.x, value.y, value.z);
	}
	else {
		color = diffuse;
	}

	return color;
}