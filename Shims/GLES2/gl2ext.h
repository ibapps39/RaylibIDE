#ifndef RLIOS_GLES2EXT_SHIM
#define RLIOS_GLES2EXT_SHIM
#if defined(__APPLE__)
  #include <OpenGLES/ES2/glext.h>
#else
  #include_next <GLES2/gl2ext.h>
#endif
#endif
