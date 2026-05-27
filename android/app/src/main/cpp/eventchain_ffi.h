// =============================================================================
//  eventchain_ffi.h  –  C-compatible ABI for Dart FFI
// =============================================================================

#ifndef EVENTCHAIN_FFI_H
#define EVENTCHAIN_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Force symbol visibility despite -fvisibility=hidden compiler flag
#define EC_API __attribute__((visibility("default")))

// Opaque handle.  Dart sees this as Pointer<Void>.
typedef void* EC_Handle;

// =============================================================================
//  Lifecycle
// =============================================================================

EC_API EC_Handle eventchain_create(const char* storageFolder, int difficulty);
EC_API void eventchain_destroy(EC_Handle handle);

EC_API const char* eventchain_last_error(void);

EC_API char* eventchain_raw_extract(EC_Handle handle, const char* stegoPath);

// FIX: removed duplicate declaration of eventchain_last_error that was here

EC_API char* eventchain_self_test(EC_Handle handle, const char* workDir);

// =============================================================================
//  String memory management
// =============================================================================

EC_API void eventchain_free_string(char* ptr);

// =============================================================================
//  Blockchain operations
// =============================================================================

EC_API int eventchain_add_ticket(EC_Handle handle,
                                 const char* eventName,
                                 const char* ticketJson);

EC_API int eventchain_validate(EC_Handle handle, const char* eventName);

EC_API int eventchain_get_size(EC_Handle handle, const char* eventName);

EC_API char* eventchain_get_chain_json(EC_Handle handle, const char* eventName);

EC_API int eventchain_transfer_ownership(EC_Handle handle,
                                         const char* eventName,
                                         int         blockIndex,
                                         const char* newOwnerName,
                                         const char* newOwnerID);

EC_API char* eventchain_get_ticket_json(EC_Handle handle,
                                        const char* eventName,
                                        int         blockIndex);

EC_API int eventchain_save(EC_Handle handle, const char* eventName);

EC_API int eventchain_load(EC_Handle handle, const char* eventName);

EC_API char* eventchain_list_events(EC_Handle handle);

// =============================================================================
//  Steganography operations
// =============================================================================

EC_API int eventchain_generate_cover(const char* outputPath, int width, int height);

EC_API int eventchain_embed_ticket(EC_Handle   handle,
                                   const char* eventName,
                                   int         blockIndex,
                                   const char* coverPath,
                                   const char* stegoPath);

EC_API int eventchain_extract_verify(EC_Handle   handle,
                                     const char* stegoPath,
                                     const char* eventName,
                                     int         blockIndex);

EC_API int eventchain_stego_capacity(int imageWidth, int imageHeight);

// =============================================================================
//  Utility
// =============================================================================

EC_API const char* eventchain_version(void);

#ifdef __cplusplus
}
#endif

#endif // EVENTCHAIN_FFI_H