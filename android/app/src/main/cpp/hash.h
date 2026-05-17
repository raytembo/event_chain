// =============================================================================
//  hash.h
//  The single hash function used everywhere in the blockchain.
//
//  Plain-English explanation:
//    1. Start with two large 64-bit buckets (a, b).
//    2. Pour every byte of the input into both buckets via XOR.
//    3. Multiply each bucket by a large prime to spread bits around.
//    4. Rotate the bits so the high bits affect the low bits.
//    5. After all bytes, stir a and b into each other one more time.
//    6. Format as a 32-char hex string.
//
//  NOTE: Not cryptographic. For production swap for SHA-256 via OpenSSL.
// =============================================================================

#ifndef HASH_H
#define HASH_H

#include <string>
#include <sstream>
#include <iomanip>
#include <cstdint>

// Produces a 32-character hex fingerprint for any input string.
inline std::string computeHash(const std::string& input)
{
    uint64_t a = 0xCAFEBABEDEAD1234ULL;
    uint64_t b = 0x1234ABCD5678EF90ULL;

    for (unsigned char c : input)
    {
        a ^= static_cast<uint64_t>(c);
        a *= 0x9E3779B97F4A7C15ULL;   // Fibonacci-derived prime
        a = (a << 13) | (a >> 51);    // rotate left 13

        b ^= static_cast<uint64_t>(c);
        b *= 0x6C62272E07BB0142ULL;
        b = (b << 17) | (b >> 47);    // rotate left 17
    }

    // Final avalanche mix
    a ^= b;
    b ^= a;
    a *= 0xBF58476D1CE4E5B9ULL;
    b *= 0x94D049BB133111EBULL;

    std::ostringstream oss;
    oss << std::hex << std::setfill('0')
        << std::setw(16) << a
        << std::setw(16) << b;
    return oss.str();
}

#endif // HASH_H
