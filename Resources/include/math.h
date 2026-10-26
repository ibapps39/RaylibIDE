#ifndef _RL_MATH_H
#define _RL_MATH_H
#define M_E 2.7182818284590452354
#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define M_PI_4 0.78539816339744830962
#define M_SQRT2 1.41421356237309504880
#define HUGE_VAL (1.0/0.0)
#define INFINITY (1.0f/0.0f)
#define NAN (0.0f/0.0f)
#define isnan(x) ((x) != (x))
#define isinf(x) ((x) == (1.0/0.0) || (x) == -(1.0/0.0))
#define isfinite(x) (!isnan(x) && !isinf(x))
double sin(double); double cos(double); double tan(double);
double asin(double); double acos(double); double atan(double); double atan2(double, double);
double sinh(double); double cosh(double); double tanh(double);
double exp(double); double exp2(double); double log(double); double log10(double); double log2(double);
double pow(double, double); double sqrt(double); double cbrt(double); double hypot(double, double);
double fabs(double); double floor(double); double ceil(double); double round(double); double trunc(double);
double fmod(double, double); double fmin(double, double); double fmax(double, double); double copysign(double, double);
long lround(double);
float sinf(float); float cosf(float); float tanf(float);
float asinf(float); float acosf(float); float atanf(float); float atan2f(float, float);
float sinhf(float); float coshf(float); float tanhf(float);
float expf(float); float exp2f(float); float logf(float); float log10f(float); float log2f(float);
float powf(float, float); float sqrtf(float); float cbrtf(float); float hypotf(float, float);
float fabsf(float); float floorf(float); float ceilf(float); float roundf(float); float truncf(float);
float fmodf(float, float); float fminf(float, float); float fmaxf(float, float); float copysignf(float, float);
#endif
