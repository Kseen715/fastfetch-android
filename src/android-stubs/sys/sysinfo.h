#pragma once
/* Forward to the real sys/sysinfo.h (struct sysinfo, sysinfo()) */
#include_next <sys/sysinfo.h>
/* get_nprocs/get_nprocs_conf added to Bionic in API 23; provide via sysconf for older targets */
#if defined(__ANDROID__) && __ANDROID_API__ < 23
#include <unistd.h>
static inline __attribute__((unused)) int get_nprocs_conf(void) { return (int)sysconf(_SC_NPROCESSORS_CONF); }
static inline __attribute__((unused)) int get_nprocs(void)      { return (int)sysconf(_SC_NPROCESSORS_ONLN); }
#endif
