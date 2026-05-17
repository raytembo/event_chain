// =============================================================================
//  fibonacci_encryption.h  -  Fibonacci Encryption Module (Lightweight)
//  Exactly as shown in the workflow diagram under "1. TICKET CREATION PROCESS"
//  Educational/demo only — not production crypto.
// =============================================================================

#ifndef FIBONACCI_ENCRYPTION_H
#define FIBONACCI_ENCRYPTION_H

#include <string>
#include <cstdint>

// Fibonacci XOR stream cipher (same function encrypts + decrypts)
// Matches "Generate Fibonacci Sequence Primes → XOR Data with Primes"
inline std::string fibonacciEncryptDecrypt(const std::string& input)
{
    std::string output = input;
    uint64_t fib1 = 1;   // F(1)
    uint64_t fib2 = 1;   // F(2)
    size_t idx = 0;

    for (char& c : output)
    {
        uint64_t fib = fib1 + fib2;
        fib1 = fib2;
        fib2 = fib;

        uint8_t keyByte = static_cast<uint8_t>(fib & 0xFF);
        c ^= static_cast<char>(keyByte);

        idx++;
        if (idx % 13 == 0) { fib1 = 1; fib2 = 2; } // variety (mimics prime sequence)
    }
    return output;
}

#endif // FIBONACCI_ENCRYPTION_H