// =============================================================================
//  block.h  -  Optimized block with fast hashing and mining limits
// =============================================================================

#ifndef BLOCK_H
#define BLOCK_H

#include <string>
#include <sstream>
#include <iostream>
#include <ctime>
#include <chrono>
#include <stdexcept>
#include "hash.h"
#include "ticket.h"
#include "config.h"

class Block
{
public:
    int         index;
    std::string timestamp;
    EventTicket data;
    std::string previousHash;
    std::string hash;
    int         nonce;

    // Constructor for new blocks
    Block(int idx, const EventTicket& ticket, const std::string& prevHash)
            : index(idx), data(ticket), previousHash(prevHash), nonce(0)
    {
        timestamp = currentTimeString();
        hash      = calculateHash();
    }

    // Empty constructor for loading blocks from file
    Block() : index(0), nonce(0) {}

    // Every field goes into the hash input.
    std::string calculateHash() const
    {
        // Pre-allocate string capacity to avoid reallocations
        std::string serialized = data.serialize();
        std::string input;
        input.reserve(64 + serialized.size() + previousHash.size() + 32);

        input += std::to_string(index);
        input += timestamp;
        input += serialized;
        input += previousHash;
        input += std::to_string(nonce);

        return computeHash(input);
    }

    // Optimized Proof-of-Work with timeout and max nonce limits
    void mine(int difficulty)
    {
        std::string target(difficulty, '0');
        const auto startTime = std::chrono::steady_clock::now();
        uint64_t checkInterval = 10000; // Check timeout every 10k iterations

        while (hash.substr(0, difficulty) != target)
        {
            // Check for timeout periodically to reduce clock overhead
            if ((nonce % checkInterval) == 0) {
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now() - startTime).count();

                if (elapsed > MINING_TIMEOUT_MS) {
                    throw std::runtime_error("Mining timeout: difficulty too high for device");
                }

                // Adaptive check interval - check less frequently as nonce grows
                if (nonce > 1000000) checkInterval = 50000;
            }

            // Hard limit to prevent infinite loops
            if (static_cast<uint64_t>(nonce) >= MAX_NONCE_ATTEMPTS) {
                throw std::runtime_error("Max nonce exceeded: " + std::to_string(MAX_NONCE_ATTEMPTS));
            }

            nonce++;
            hash = calculateHash();
        }

        std::cout << "    nonce=" << nonce << "  hash=" << hash << "\n";
    }

    // Tamper check
    bool isIntact() const { return (hash == calculateHash()); }

private:
    std::string currentTimeString() const
    {
        time_t now = time(nullptr);
        char   buf[32];
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", localtime(&now));
        return std::string(buf);
    }
};

#endif // BLOCK_H