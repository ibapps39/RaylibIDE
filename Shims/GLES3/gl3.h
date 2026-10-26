// Maps raylib's <GLES3/gl3.h> onto Apple's OpenGLES, and redirects the "default
// framebuffer 0" to the CAEAGLLayer-backed FBO (iOS has no real FBO 0).
#ifndef RLIOS_GLES3_SHIM
#define RLIOS_GLES3_SHIM
#if defined(__APPLE__)
  #include <OpenGLES/ES3/gl.h>
  #include <OpenGLES/ES3/glext.h>
  extern unsigned int rlios_default_fbo;
  static inline void rlios_BindFramebuffer(GLenum target, GLuint fb)
  {
      glBindFramebuffer(target, fb == 0 ? rlios_default_fbo : fb);
  }
  #define glBindFramebuffer rlios_BindFramebuffer

  // raylib's ES3 path uses EXT/OES names that are core in ES3 / absent from Apple's headers
  #define glDrawBuffersEXT glDrawBuffers
  #ifndef GL_COLOR_ATTACHMENT0_EXT
    #define GL_COLOR_ATTACHMENT0_EXT GL_COLOR_ATTACHMENT0
    #define GL_COLOR_ATTACHMENT1_EXT GL_COLOR_ATTACHMENT1
    #define GL_COLOR_ATTACHMENT2_EXT GL_COLOR_ATTACHMENT2
    #define GL_COLOR_ATTACHMENT3_EXT GL_COLOR_ATTACHMENT3
    #define GL_COLOR_ATTACHMENT4_EXT GL_COLOR_ATTACHMENT4
    #define GL_COLOR_ATTACHMENT5_EXT GL_COLOR_ATTACHMENT5
    #define GL_COLOR_ATTACHMENT6_EXT GL_COLOR_ATTACHMENT6
    #define GL_COLOR_ATTACHMENT7_EXT GL_COLOR_ATTACHMENT7
  #endif
  #ifndef GL_RGBA32F_EXT
    #define GL_RGBA32F_EXT 0x8814
    #define GL_RGB32F_EXT  0x8815
    #define GL_RGBA16F_EXT 0x881A
    #define GL_RGB16F_EXT  0x881B
    #define GL_R32F_EXT    0x822E
    #define GL_R16F_EXT    0x822D
  #endif
  #ifndef GL_RED_EXT
    #define GL_RED_EXT 0x1903
  #endif
  #ifndef GL_HALF_FLOAT_OES
    #define GL_HALF_FLOAT_OES 0x8D61
  #endif
  #ifndef GL_MIRROR_CLAMP_EXT
    #define GL_MIRROR_CLAMP_EXT 0x8742
  #endif
  #ifndef GL_TEXTURE_MAX_ANISOTROPY_EXT
    #define GL_TEXTURE_MAX_ANISOTROPY_EXT 0x84FE
    #define GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT 0x84FF
  #endif
  #ifndef GL_ETC1_RGB8_OES
    #define GL_ETC1_RGB8_OES 0x8D64
  #endif
  #ifndef GL_DEPTH_COMPONENT24_OES
    #define GL_DEPTH_COMPONENT24_OES 0x81A6
    #define GL_DEPTH_COMPONENT32_OES 0x81A7
  #endif
#else
  #include_next <GLES3/gl3.h>   // Linux syntax-check builds only
  extern unsigned int rlios_default_fbo;
  #define GL_GLEXT_PROTOTYPES 1
#endif
#endif
