#pragma once
#include <stdlib.h>
typedef struct { int gl_pathc; char **gl_pathv; int gl_offs; } glob_t;
#define GLOB_NOSORT   0
#define GLOB_ERR      0
#define GLOB_MARK     0
#define GLOB_NOCHECK  0
#define GLOB_APPEND   0
#define GLOB_NOESCAPE 0
#define GLOB_NOMATCH  (-3)
#define GLOB_NOSPACE  (-1)
static inline __attribute__((unused))
int glob(const char *p, int f, int (*e)(const char*,int), glob_t *g) {
    (void)p;(void)f;(void)e; g->gl_pathc=0; g->gl_pathv=NULL; return GLOB_NOMATCH;
}
static inline __attribute__((unused)) void globfree(glob_t *g) { (void)g; }
