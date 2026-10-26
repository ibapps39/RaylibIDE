#ifndef _RL_TIME_H
#define _RL_TIME_H
#include <stddef.h>
typedef long time_t;
typedef unsigned long clock_t;
#define CLOCKS_PER_SEC 1000000
struct timespec { long tv_sec; long tv_nsec; };
struct tm { int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst; long tm_gmtoff; char *tm_zone; };
time_t time(time_t *);
clock_t clock(void);
double difftime(time_t, time_t);
struct tm *localtime(const time_t *);
struct tm *gmtime(const time_t *);
time_t mktime(struct tm *);
size_t strftime(char *, size_t, const char *, const struct tm *);
#endif
