#pragma once
/* Bionic gained <utmpx.h> at API 23; r16b has none. These devices keep no utmp
   database, so provide the type plus no-op accessors (getutxent -> NULL means
   "no logged-in users"). Detected by CMake's CHECK_INCLUDE_FILE(utmpx.h), which
   then sets FF_HAVE_UTMPX=1 and selects the utmpx code path in users_linux.c.
   Modern NDKs (API >= 23) forward to the real header. */
#if defined(__ANDROID__) && __ANDROID_API__ < 23
#include <stdint.h>
#include <sys/time.h>

#ifndef USER_PROCESS
#define USER_PROCESS 7
#endif

struct utmpx {
    short          ut_type;
    char           ut_user[32];
    char           ut_line[32];
    char           ut_host[256];
    int32_t        ut_addr_v6[4];
    struct timeval ut_tv;
};

static inline __attribute__((unused)) void          setutxent(void) {}
static inline __attribute__((unused)) struct utmpx* getutxent(void) { return (struct utmpx*)0; }
static inline __attribute__((unused)) void          endutxent(void) {}
#else
#include_next <utmpx.h>
#endif
