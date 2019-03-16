#include <optix_world.h>
#include <curand_kernel.h>
#include "math_constants.h"

__device__ optix::float3 sampleHemisphere(optix::float3 normal, curandState_t* state, float& pdf);

struct PerRayData_radiance
{
	optix::float3 result;
	float  importance;
	int depth;
	curandState_t* state;

};

struct PerRayData_shadow
{
	optix::float3 attenuation;
	optix::uchar1 visible;
};
