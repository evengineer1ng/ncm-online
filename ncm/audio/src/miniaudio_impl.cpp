// miniaudio (public domain / MIT-0) with stb_vorbis (public domain / MIT) for the OGG Vorbis clips, compiled once here.
// The order is the one miniaudio documents for Vorbis support.
#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#undef STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"
