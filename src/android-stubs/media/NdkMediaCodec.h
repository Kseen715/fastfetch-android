#pragma once
/* NDK r16b predates the AMediaCodec API entirely. fastfetch's codec_android.c
   loads these symbols at runtime via dlopen/dlsym and only needs the
   declarations to compile; on old devices the dlopen simply fails and codec
   detection is skipped. For modern NDKs (API >= 21) forward to the real header. */
#if defined(__ANDROID__) && __ANDROID_API__ < 21
#include <stdint.h>

typedef enum { AMEDIA_OK = 0 } media_status_t;
typedef struct AMediaCodec AMediaCodec;

AMediaCodec*   AMediaCodec_createDecoderByType(const char* mime_type);
AMediaCodec*   AMediaCodec_createEncoderByType(const char* mime_type);
media_status_t AMediaCodec_delete(AMediaCodec* codec);
media_status_t AMediaCodec_getName(AMediaCodec* codec, char** out_name);
void           AMediaCodec_releaseName(AMediaCodec* codec, char* name);
#else
#include_next <media/NdkMediaCodec.h>
#endif
