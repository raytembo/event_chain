cmake_minimum_required(VERSION 3.22.1)
project(EventChain CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 16 KB page-size alignment required for Android 15+ ELF binaries
set(CMAKE_SHARED_LINKER_FLAGS "-Wl,-z,max-page-size=16384")

# ── Compiler flags ────────────────────────────────────────────────────────────
# FIX: Appended -fexceptions and -frtti so your try/catch FFI wrappers function correctly.
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -fomit-frame-pointer -fexceptions -frtti")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections -fdata-sections")

# ── ARM-specific optimisations ────────────────────────────────────────────────
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a")
endif()

# ── Library target ────────────────────────────────────────────────────────────
# NOTE: If EventManager has a separate .cpp implementation file, add it here!
set(SOURCES 
    eventchain_ffi.cpp
)

add_library(EventChain SHARED ${SOURCES})

# ── Target Compile Definitions ────────────────────────────────────────────────
# Modern CMake replacement for add_definitions(). Scopes macros tightly to this library.
target_compile_definitions(EventChain PRIVATE
    cimg_use_stb
    cimg_display=0
    MINE_DIFFICULTY=2
    MAX_NONCE_ATTEMPTS=10000000ULL
    MINING_TIMEOUT_MS=30000
    MAX_IMAGE_DIMENSION=1024
    CIMG_NO_OPENMP
)

# ── Include Directories ───────────────────────────────────────────────────────
target_include_directories(EventChain PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}          # eventchain_ffi.h, eventmanager.h
        ${CMAKE_CURRENT_SOURCE_DIR}/stego    # steganography.h, CImg.h
        ${CMAKE_CURRENT_SOURCE_DIR}/stb      # stb_image_write.h, stb_image.h
)

# ── Linker Dependencies ───────────────────────────────────────────────────────
find_library(log-lib log)
target_link_libraries(EventChain PRIVATE ${log-lib})

# Strip unused internal symbols, keeping the binary size lean. 
# Remember to tag FFI functions with __attribute__((visibility("default"))) in headers!
set_target_properties(EventChain PROPERTIES
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
)