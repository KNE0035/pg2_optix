#include "pch.h"
#include "camera.h"
#include "raytracer.h"
#include "utils.h"
Camera::Camera( const int width, const int height, const float fov_y,
	const Vector3 view_from, const Vector3 view_at )
{
	width_ = width;
	height_ = height;
	fov_y_ = fov_y;

	view_from_ = view_from;
	view_at_ = view_at;

	// TODO compute focal lenght based on the vertical field of view and the camera resolution
	f_y_ = height  / (2 * tanf(fov_y * 0.5f));
	
	// TODO build M_c_w_ matrix	
	
	recalculateMcw();
}

float Camera::focalLength() {
	return f_y_;
}
Matrix3x3 Camera::M_c_w() {
	return M_c_w_;
}
Vector3 Camera::view_from(){
	return view_from_;
}

Vector3 Camera::view_at(){
	return view_at_;
}

void Camera::updateFov(const float fov_y) {
	f_y_ = height_ / (2 * tanf(fov_y * 0.5f));
}

Vector3 Camera::up() {
	return up_;
}

void Camera::recalculateMcw() {
	if (!mcwUpdate) return;

	basis_z = view_from_ - view_at_;
	basis_z.Normalize();

	basis_x = up_.CrossProduct(basis_z);
	basis_x.Normalize();

	basis_y = basis_z.CrossProduct(basis_x);
	basis_y.Normalize();

	up_ = basis_y;

	M_c_w_ = Matrix3x3(basis_x, basis_y, basis_z);
	mcwUpdate = false;
}


void Camera::moveForward(double frameStep) {
	view_at_ = view_at_ - frameStep * basis_z;
	view_from_ = view_from_ - frameStep * basis_z;
	mcwUpdate = true;
}

void Camera::moveRight(double frameStep){
	view_at_ = view_at_ + frameStep * basis_x;
	view_from_ = view_from_ + frameStep * basis_x;
	mcwUpdate = true;
}
void Camera::rotateRight(double frameStep){
	double forwardL = (view_at_ - view_from_).L2Norm();
	Vector3 newViewAt = view_at_ + basis_x * frameStep;
	double distanceRatio = forwardL / (newViewAt - view_from_).L2Norm();
	Vector3 newVector = (newViewAt - view_from_);
	newVector *= distanceRatio;
	newViewAt = view_from_ + newVector;
	view_at_ = newViewAt;
	mcwUpdate = true;
}

void Camera::rotateUp(double frameStep){
	Vector3 newViewAt = view_at_ + basis_y * frameStep;
	view_at_ = newViewAt;
	mcwUpdate = true;
}

void Camera::rollRight(double frameStep){
	up_ = basis_y + 0.01 * frameStep * basis_x;
	mcwUpdate = true;
}

