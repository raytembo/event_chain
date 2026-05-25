# =============================================================================
#  CMakeLists.txt  —  Android NDK r27 compatible build (BMP + PNG C++ layer)
# =============================================================================
#
#  PNG read/write strategy
#  ───────────────────────
#  Writing PNG  →  stb_image_write.h  (header-only, zero external deps)
#  Reading PNG  →  stb_image.h        (header-only, zero external deps)
#                  enabled inside CImg via -Dcimg_use_stb
#
#  Without -Dcimg_use_stb, CImg::load() on a .png file calls its internal
#  load_png() which requires libpng (cimg_use_png).  libpng is NOT linked
#  here, so that call throws CImgIOException at runtime — silently caught
#  in DCTSteganography::embed() — producing the "embedTicket returned false"
#  failure even when the cover image exists and is valid.
#
#  JPEG/WebP are intentionally unsupported as cover/stego formats: lossy
#  compression destroys the DCT payload.  Format conversion must be done
#  in Dart (dart:ui codec → PNG) before the path is passed to the C++ layer.
# =============================================================================

cmake_minimum_required(VERSION 3.22.1)
project(EventChain CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 16 KB page-size alignment required for Android 15+
set(CMAKE_SHARED_LINKER_FLAGS "-Wl,-z,max-page-size=16384")

# ── Compiler optimisation flags ───────────────────────────────────────────────
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -fomit-frame-pointer")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections -fdata-sections")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=hidden")

# ── Preprocessor definitions ──────────────────────────────────────────────────

# cimg_use_stb   MUST be defined before CImg.h is included anywhere.
# CMake passes it as a compiler flag so it is visible in every translation
# unit, including headers pulled in transitively (steganography.h → CImg.h).
# This replaces the missing libpng dependency for PNG read support.
add_definitions(-Dcimg_use_stb)

# Disable CImg's display/GUI subsystem — not available on Android.
add_definitions(-Dcimg_display=0)

# Proof-of-Work difficulty and safety limits
add_definitions(-DMINE_DIFFICULTY=2)
add_definitions(-DMAX_NONCE_ATTEMPTS=10000000ULL)
add_definitions(-DMINING_TIMEOUT_MS=30000)

# Cap image dimensions to limit RAM usage on low-end devices
add_definitions(-DMAX_IMAGE_DIMENSION=1024)

# Disable CImg's OpenMP auto-detection (not needed, avoids linking issues)
add_definitions(-DCIMG_NO_OPENMP)

# ── ARM-specific optimisations ────────────────────────────────────────────────
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a")
endif()

# ── Library target ────────────────────────────────────────────────────────────
set(SOURCES eventchain_ffi.cpp)

add_library(EventChain SHARED ${SOURCES})

target_include_directories(EventChain PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}          # eventchain_ffi.h, eventmanager.h, …
        ${CMAKE_CURRENT_SOURCE_DIR}/stego    # steganography.h, CImg.h
        ${CMAKE_CURRENT_SOURCE_DIR}/stb      # stb_image_write.h, stb_image.h
)

find_library(log-lib log)
target_link_libraries(EventChain ${log-lib})

set_target_properties(EventChain PROPERTIES
        CXX_VISIBILITY_PRESET hidden
)