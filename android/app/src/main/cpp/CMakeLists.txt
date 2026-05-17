# =============================================================================
#  CMakeLists.txt  —  Android NDK r27 compatible build (BMP + PNG C++ layer)
# =============================================================================
#  The C++ steganography layer handles BMP and PNG formats.
#  PNG is written via stb_image_write.h (header-only, no libpng needed).
#  JPEG/WebP are intentionally unsupported in the C++ layer — lossy
#  compression destroys DCT steganography payloads.
#  Any further format conversion is done in Dart using the 'image' package.
# =============================================================================

cmake_minimum_required(VERSION 3.22.1)
project(EventChain CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 16KB page size support for Android 15+
set(CMAKE_SHARED_LINKER_FLAGS "-Wl,-z,max-page-size=16384")

# Compiler flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -fomit-frame-pointer")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections -fdata-sections")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=hidden")

# Definitions — ONLY BMP support in C++, no libpng/libjpeg needed
add_definitions(-Dcimg_display=0)
add_definitions(-DMINE_DIFFICULTY=2)
add_definitions(-DMAX_NONCE_ATTEMPTS=10000000ULL)
add_definitions(-DMINING_TIMEOUT_MS=30000)
add_definitions(-DMAX_IMAGE_DIMENSION=1024)
add_definitions(-DCIMG_NO_OPENMP)

# ARM optimizations
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a")
endif()

set(SOURCES eventchain_ffi.cpp)

add_library(EventChain SHARED ${SOURCES})

target_include_directories(EventChain PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/stego
        ${CMAKE_CURRENT_SOURCE_DIR}/stb          # stb_image_write.h lives here
)

find_library(log-lib log)
target_link_libraries(EventChain ${log-lib})

set_target_properties(EventChain PROPERTIES
        CXX_VISIBILITY_PRESET hidden
)