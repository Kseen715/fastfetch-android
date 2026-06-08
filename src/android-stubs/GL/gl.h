#pragma once
/* Android NDK has EGL but not desktop GL/gl.h.
   fastfetch auto-detects EGL via __has_include, then includes GL/gl.h for type defs.
   Redirect to GLES which provides the same base types. */
#include <GLES/gl.h>
