#include <optix_world.h>

struct PerRayData_radiance
{
	optix::float3 result;
	float  importance;
	int depth;
};

struct PerRayData_shadow
{
	optix::float3 attenuation;
};
