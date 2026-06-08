#pragma once
/* getifaddrs/freeifaddrs added to Bionic in API 24.
   Static inline stubs for older targets — no dynamic symbol dependency,
   safe to run on API 21 devices. Local IP detection returns ENOSYS. */
#if defined(__ANDROID__) && __ANDROID_API__ < 24
#include <errno.h>
#include <sys/socket.h>
struct ifaddrs {
    struct ifaddrs  *ifa_next;
    char            *ifa_name;
    unsigned int     ifa_flags;
    struct sockaddr *ifa_addr;
    struct sockaddr *ifa_netmask;
    struct sockaddr *ifa_broadaddr;
    void            *ifa_data;
};
static inline __attribute__((unused)) int getifaddrs(struct ifaddrs **ifap) {
    (void)ifap; errno = ENOSYS; return -1;
}
static inline __attribute__((unused)) void freeifaddrs(struct ifaddrs *ifa) { (void)ifa; }
#else
#include_next <ifaddrs.h>
#endif
