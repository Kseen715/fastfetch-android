#pragma once
/* Compatibility shims for old Bionic (NDK r16b legacy builds: armv5/armv6/armv7).
   Each function became part of Bionic at the API level noted; below that level
   the system header hides the prototype, so we supply a static-inline version
   that compiles into the binary instead of becoming an unresolved dynamic
   symbol (which would fail to load on the old devices these builds target).
   Force-included for API < 21 via the build script. */

/* ---- getline / getdelim : Bionic API 18 ---- */
#include <stdio.h>
#if defined(__ANDROID__) && __ANDROID_API__ < 18
#include <stdlib.h>
#include <errno.h>

static inline __attribute__((unused))
ssize_t getdelim(char **lineptr, size_t *n, int delim, FILE *stream) {
    if (lineptr == NULL || n == NULL || stream == NULL) { errno = EINVAL; return -1; }
    if (*lineptr == NULL || *n == 0) {
        *n = 128;
        char *buf = (char *)realloc(*lineptr, *n);
        if (buf == NULL) { errno = ENOMEM; return -1; }
        *lineptr = buf;
    }
    size_t pos = 0;
    int c;
    while ((c = getc(stream)) != EOF) {
        if (pos + 1 >= *n) {
            size_t newsize = *n * 2;
            char *buf = (char *)realloc(*lineptr, newsize);
            if (buf == NULL) { errno = ENOMEM; return -1; }
            *lineptr = buf;
            *n = newsize;
        }
        (*lineptr)[pos++] = (char)c;
        if (c == delim) break;
    }
    if (pos == 0 && c == EOF) return -1;
    (*lineptr)[pos] = '\0';
    return (ssize_t)pos;
}

static inline __attribute__((unused))
ssize_t getline(char **lineptr, size_t *n, FILE *stream) {
    return getdelim(lineptr, n, '\n', stream);
}
#endif

/* ---- faccessat : Bionic API 16 ---- */
#if defined(__ANDROID__) && __ANDROID_API__ < 16
#include <unistd.h>
static inline __attribute__((unused))
int faccessat(int dirfd, const char *path, int mode, int flags) {
    (void)dirfd; (void)flags;   /* assume AT_FDCWD; flags unsupported pre-16 */
    return access(path, mode);
}
#endif

/* ---- statvfs / fstatvfs : Bionic API 19 (struct is always defined) ---- */
#if defined(__ANDROID__) && __ANDROID_API__ < 19
#include <sys/statvfs.h>
#include <sys/statfs.h>

static inline __attribute__((unused))
void ff__statfs_to_statvfs(const struct statfs *s, struct statvfs *out) {
    out->f_bsize   = (unsigned long)s->f_bsize;
    out->f_frsize  = (unsigned long)(s->f_frsize ? s->f_frsize : s->f_bsize);
    out->f_blocks  = s->f_blocks;
    out->f_bfree   = s->f_bfree;
    out->f_bavail  = s->f_bavail;
    out->f_files   = s->f_files;
    out->f_ffree   = s->f_ffree;
    out->f_favail  = s->f_ffree;
    out->f_fsid    = 0;
    out->f_flag    = 0;
    out->f_namemax = (unsigned long)s->f_namelen;
}
static inline __attribute__((unused))
int statvfs(const char *path, struct statvfs *out) {
    struct statfs s;
    if (statfs(path, &s) != 0) return -1;
    ff__statfs_to_statvfs(&s, out);
    return 0;
}
static inline __attribute__((unused))
int fstatvfs(int fd, struct statvfs *out) {
    struct statfs s;
    if (fstatfs(fd, &s) != 0) return -1;
    ff__statfs_to_statvfs(&s, out);
    return 0;
}
#endif

/* ---- setmntent / endmntent : Bionic API 21 (getmntent is older) ---- */
#if defined(__ANDROID__) && __ANDROID_API__ < 21
#include <mntent.h>
static inline __attribute__((unused))
FILE *setmntent(const char *filename, const char *type) { return fopen(filename, type); }
static inline __attribute__((unused))
int endmntent(FILE *fp) { if (fp) fclose(fp); return 1; }

/* Bionic's getmntent is an unimplemented stub before API 21: it prints
   "getmntent() is not implemented" / "FIX ME!" to stderr and returns NULL.
   Replace it with a real /proc/mounts parser (setmntent above is fopen).
   The macro redirects call sites; the real declaration from <mntent.h> stays. */
#include <stdio.h>
#include <string.h>
static inline __attribute__((unused))
struct mntent *ffcompat_getmntent(FILE *fp) {
    static char line[1024];
    static struct mntent ent;
    static char fsname[256], dir[256], type[64], opts[256];
    while (fp && fgets(line, sizeof(line), fp)) {
        if (line[0] == '#' || line[0] == '\n')
            continue;
        if (sscanf(line, "%255s %255s %63s %255s %d %d",
                   fsname, dir, type, opts, &ent.mnt_freq, &ent.mnt_passno) >= 4) {
            ent.mnt_fsname = fsname;
            ent.mnt_dir    = dir;
            ent.mnt_type   = type;
            ent.mnt_opts   = opts;
            return &ent;
        }
    }
    return (struct mntent *)0;
}
#define getmntent ffcompat_getmntent
#endif

/* ---- ttyname : Bionic's pre-API-26 stub prints a noisy FIXME to stderr ---- */
#if defined(__ANDROID__) && __ANDROID_API__ < 26
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
static inline __attribute__((unused))
char *ffcompat_ttyname(int fd) {
    static char buf[256];
    if (!isatty(fd)) { errno = ENOTTY; return (char *)0; }
    char path[64];
    snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(path, buf, sizeof(buf) - 1);
    if (n < 0) return (char *)0;
    buf[n] = '\0';
    return buf;
}
#define ttyname ffcompat_ttyname
#endif
