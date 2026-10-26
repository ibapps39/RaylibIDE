#ifndef _RL_ASSERT_H
#define _RL_ASSERT_H
#include <stdio.h>
#include <stdlib.h>
static void __rl_assert_fail(const char *e, const char *f, int l) { fprintf(stderr, "Assertion failed: %s (%s:%d)\n", e, f, l); abort(); }
#ifdef NDEBUG
#define assert(e) ((void)0)
#else
#define assert(e) ((e) ? (void)0 : __rl_assert_fail(#e, __FILE__, __LINE__))
#endif
#endif
