#!/usr/bin/cmake -P

# Usage:
# - cmake script mode: cmake -P glesw_gen.cmake or ./glesw_gen.cmake
# - from a cmake project: include(glesw_gen) then glesw_gen(OUTPUT_PATH)
# Pavel Rojtberg 2016

function(glesw_gen OUTDIR)
set(UNLICENSE
"/*

    This file was generated with glesw_gen.cmake, part of glXXw
    (hosted at https://github.com/paroj/glXXw-cmake)

    This is free and unencumbered software released into the public domain.

    Anyone is free to copy, modify, publish, use, compile, sell, or
    distribute this software, either in source code form or as a compiled
    binary, for any purpose, commercial or non-commercial, and by any
    means.

    In jurisdictions that recognize copyright laws, the author or authors
    of this software dedicate any and all copyright interest in the
    software to the public domain. We make this dedication for the benefit
    of the public at large and to the detriment of our heirs and
    successors. We intend this dedication to be an overt act of
    relinquishment in perpetuity of all present and future rights to this
    software under copyright law.

    THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
    OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
    ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.

*/\n
")

set(HDR_DIR GLES3)

file(MAKE_DIRECTORY ${OUTDIR}/include/GLES2)
file(MAKE_DIRECTORY ${OUTDIR}/include/${HDR_DIR})
file(MAKE_DIRECTORY ${OUTDIR}/src)

set(API_LIST GLES3/gl3.h GLES2/gl2ext.h)

foreach(APIFILE ${API_LIST})
    get_filename_component(APINAME ${APIFILE} NAME)
    if(NOT EXISTS ${OUTDIR}/include/${APIFILE})
        message(STATUS "Downloading ${APINAME} to ${APIFILE}...")
        file(DOWNLOAD
            https://www.khronos.org/registry/gles/api/${APIFILE}
            ${OUTDIR}/include/${APIFILE})
    else()
        message(STATUS "Reusing ${APINAME} from ${APIFILE}...")
    endif()

    message(STATUS "Parsing ${APINAME} header...")

    file(STRINGS ${OUTDIR}/include/${APIFILE} APICONTENTS)

    foreach(LINE ${APICONTENTS})
        string(REGEX MATCH "GL_APICALL.*GL_APIENTRY[ ]+([a-zA-Z0-9_]+)" MATCHES ${LINE})
        if(MATCHES)
            list(APPEND PROCS ${CMAKE_MATCH_1})
        endif()
    endforeach()
endforeach()

list(SORT PROCS)

set(SPACES "                                                       ") # 55 spaces

macro(getproctype PROC)
    string(TOUPPER ${PROC} P_T)
    set(P_T "PFN${P_T}PROC")
endmacro()

macro(getproctype_aligned PROC)
    getproctype(${PROC})
    string(LENGTH ${P_T} LEN)
    math(EXPR LEN "55 - ${LEN}")
    string(SUBSTRING ${SPACES} 0 ${LEN} PAD)
    set(P_T "${P_T}${PAD}")
endmacro()

macro(getprocsignature PROC)
    string(SUBSTRING ${PROC} 2 -1 P_S)
    set(P_S "glesw${P_S}")
endmacro()

message(STATUS "Generating glesw.h in include/${HDR_DIR}...")

set(HDR_OUT ${OUTDIR}/include/${HDR_DIR}/glesw.h)
file(WRITE ${HDR_OUT} ${UNLICENSE})
file(APPEND ${HDR_OUT}
"#ifndef __glesw_h_
#define __glesw_h_

#include <GLES3/gl3.h>
#include <KHR/khrplatform.h>
#include <GLES3/gl3platform.h>
#include <GLES2/gl2ext.h>

#ifdef __cplusplus
extern \"C\" {
#endif

typedef void (*GLESWglProc)(void);
typedef GLESWglProc (*GLESWGetProcAddressProc)(const char *proc);

/* glesw api */
int gleswInit(void);
int gleswInit2(GLESWGetProcAddressProc proc);
int gleswIsSupported(int major, int minor);
GLESWglProc gleswGetProcAddress(const char *proc);

/* OpenGL functions */
")

foreach(PROC ${PROCS})
    getprocsignature(${PROC})
    getproctype_aligned(${PROC})
    file(APPEND ${HDR_OUT} "extern ${P_T} ${P_S};\n")
endforeach()

foreach(PROC ${PROCS})
    string(SUBSTRING ${PROC} 2 -1 P_S)
    string(LENGTH ${PROC} LEN)
    math(EXPR LEN "54 - ${LEN}")
    string(SUBSTRING ${SPACES} 0 ${LEN} PAD)
    file(APPEND ${HDR_OUT} "#define ${PROC}${PAD} glesw${P_S}\n")
endforeach()

file(APPEND ${HDR_OUT}
"
#ifdef __cplusplus
}
#endif

#endif
")

message(STATUS "Generating glesw.c in src...")
set(SRC_OUT ${OUTDIR}/src/glesw.c)
file(WRITE ${SRC_OUT} ${UNLICENSE})
file(APPEND ${SRC_OUT} "#include <${HDR_DIR}/glesw.h>
#include <stdio.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN 1
#include <windows.h>
#include <EGL/egl.h>

static HMODULE libgl;

static void open_libgl(void)
{
    libgl = LoadLibraryA(\"libGLESv2.dll\");
}

static void close_libgl(void)
{
    FreeLibrary(libgl);
}

static GLESWglProc get_proc(const char *proc)
{
    GLESWglProc res;

    res = (GLESWglProc)eglGetProcAddress(proc);
    if (!res)
        res = (GLESWglProc)GetProcAddress(libgl, proc);
    return res;
}
#elif defined(__APPLE__) || defined(__APPLE_CC__)
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIDevice.h>

CFBundleRef bundle;
CFURLRef bundleURL;

static void open_libgl(void)
{
    bundle = CFBundleGetBundleWithIdentifier(CFSTR(\"com.apple.opengles\")); // we are always linked to OpenGLES.framework statically, so it is already loaded and could be found by id
    assert(bundle != NULL);
    
    CFRetain(bundle);
    bundleURL = CFBundleCopyBundleURL(bundle);
}

static void close_libgl(void)
{
    CFRelease(bundle);
    CFRelease(bundleURL);
}

static GLESWglProc get_proc(const char *proc)
{
    GLESWglProc res;

    CFStringRef procname = CFStringCreateWithCString(kCFAllocatorDefault, proc,
                                                     kCFStringEncodingASCII);
    *(void **)(&res) = CFBundleGetFunctionPointerForName(bundle, procname);
    CFRelease(procname);
    return res;
}
#elif defined(__EMSCRIPTEN__)
#include <EGL/egl.h>
static void open_libgl() {}
static void close_libgl() {}
static GLESWglProc get_proc(const char *proc)
{
    return (GLESWglProc)eglGetProcAddress(proc);
}
#else
#include <dlfcn.h>

static void *libgl;

static void open_libgl(void)
{
    libgl = dlopen(\"libGLESv2.so\", RTLD_LAZY | RTLD_GLOBAL);
}

static void close_libgl(void)
{
    dlclose(libgl);
}

static GLESWglProc get_proc(const char *proc)
{
    return dlsym(libgl, proc);
}
#endif

static struct {
	int major, minor;
} version;

static int parse_version(void)
{
	if (!glGetString)
		return -1;

	const char* pcVer = (const char*)glGetString(GL_VERSION);
	sscanf(pcVer, \"OpenGL ES %u.%u\", &version.major, &version.minor);

	if (version.major < 2)
		return -1;
	return 0;
}

static void load_procs(GLESWGetProcAddressProc proc);

int gleswInit(void)
{
	open_libgl();
	load_procs(get_proc);
	close_libgl();
	return parse_version();
}

int gleswInit2(GLESWGetProcAddressProc proc)
{
	load_procs(proc);
	return parse_version();
}

int gleswIsSupported(int major, int minor)
{
	if (major < 2)
		return 0;
	if (version.major == major)
		return version.minor >= minor;
	return version.major >= major;
}

GLESWglProc gleswGetProcAddress(const char *proc)
{
	return get_proc(proc);
}

")

foreach(PROC ${PROCS})
    getprocsignature(${PROC})
    getproctype_aligned(${PROC})
    file(APPEND ${SRC_OUT} "${P_T} ${P_S};\n")
endforeach()

file(APPEND ${SRC_OUT} "
static void load_procs(GLESWGetProcAddressProc proc)
{\n")

foreach(PROC ${PROCS})
    getprocsignature(${PROC})
    getproctype(${PROC})
    file(APPEND ${SRC_OUT} "\t${P_S} = (${P_T})proc(\"${PROC}\");\n")
endforeach()

file(APPEND ${SRC_OUT} "}\n")
endfunction()

if(NOT CMAKE_PROJECT_NAME)
    glesw_gen(".")
endif()
