// =============================================================================
//  config.h
//  Global constants with adaptive difficulty support.
//  FIX: Added `inline` to all `const std::string` / `const int` at namespace
//  scope to prevent ODR violations if this header is ever included in more than
//  one translation unit.
// =============================================================================

#ifndef CONFIG_H
#define CONFIG_H

#include <string>
#include <cstdint>

// Magic bytes written at the very start of every .etchain file.
inline const std::string MAGIC_HEADER    = "WEB3CHAIN_V1";
inline const std::string FILE_EXT        = ".web3chain";

// Proof-of-Work difficulty: how many leading '0' characters the hash must have.
#ifndef MINE_DIFFICULTY
inline const int         MINE_DIFFICULTY = 2;
#endif

// Maximum nonce attempts before timeout (prevents infinite loops on slow devices)
#ifndef MAX_NONCE_ATTEMPTS
inline const uint64_t    MAX_NONCE_ATTEMPTS = 10000000ULL;  // 10 million
#endif

// Mining timeout in milliseconds (30 seconds)
#ifndef MINING_TIMEOUT_MS
inline const int         MINING_TIMEOUT_MS = 30000;
#endif

// Steganography QIM step size - MUST be constexpr for static member initialization
#ifndef STEGO_QIM_STEP
#define STEGO_QIM_STEP 50.0
#endif

// Maximum image dimension for low-end devices (reduce memory usage)
#ifndef MAX_IMAGE_DIMENSION
inline const int         MAX_IMAGE_DIMENSION = 1024;
#endif

#endif // CONFIG_H