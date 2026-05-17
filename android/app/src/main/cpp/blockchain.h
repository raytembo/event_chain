// =============================================================================
//  blockchain.h  -  Optimized blockchain with efficient re-mining
// =============================================================================

#ifndef BLOCKCHAIN_H
#define BLOCKCHAIN_H

#include <vector>
#include <string>
#include <iostream>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <cstdint>
#include <stdexcept>
#include <ctime>

#include "config.h"
#include "hash.h"
#include "block.h"
#include "ticket.h"

class Blockchain {
public:
    explicit Blockchain(int difficulty = MINE_DIFFICULTY)
            : difficulty_(difficulty)
    {
        chain_.push_back(createGenesisBlock());
    }

    void addTicket(const EventTicket& ticket)
    {
        const std::string& prev_hash = chain_.back().hash;
        Block new_block((int)chain_.size(), ticket, prev_hash);
        new_block.mine(difficulty_);
        chain_.push_back(std::move(new_block));
    }

    bool validate(bool verbose = false) const
    {
        for (std::size_t i = 1; i < chain_.size(); ++i) {
            const Block& cur  = chain_[i];
            const Block& prev = chain_[i - 1];
            if (!cur.isIntact()) {
                if (verbose)
                    std::cout << "  [FAIL] Block #" << i << " hash mismatch\n";
                return false;
            }
            if (cur.previousHash != prev.hash) {
                if (verbose)
                    std::cout << "  [FAIL] Block #" << i << " broken link\n";
                return false;
            }
        }
        return true;
    }

    bool tryReplaceWith(std::vector<Block> candidate)
    {
        Blockchain temp(difficulty_);
        temp.chain_ = std::move(candidate);
        if (temp.validate() && temp.chain_.size() > chain_.size()) {
            chain_ = std::move(temp.chain_);
            return true;
        }
        return false;
    }

    const EventTicket& getTicket(std::size_t index) const
    {
        if (index >= chain_.size())
            throw std::out_of_range("Block index out of range");
        return chain_[index].data;
    }

    void print() const
    {
        std::cout << "\n" << std::string(70, '=') << "\n";
        std::cout << "  EVENT CHAIN  (" << chain_.size() << " blocks)\n";
        std::cout << std::string(70, '=') << "\n\n";
        for (const auto& block : chain_) {
            std::cout << "  Block #" << block.index;
            if (block.index == 0) std::cout << " [GENESIS]";
            std::cout << "\n";
            std::cout << "    Timestamp   : " << block.timestamp << "\n";
            std::cout << "    Ticket ID   : " << block.data.ticketID << "\n";
            std::cout << "    Event       : " << block.data.eventName << "\n";
            std::cout << "    Date        : " << block.data.eventDate << "\n";
            std::cout << "    Venue       : " << block.data.venue << "\n";
            std::cout << "    Owner       : " << block.data.ownerName
                      << " (" << block.data.ownerID << ")\n";
            std::cout << "    Type        : " << block.data.ticketType
                      << "    Price: $" << std::fixed << std::setprecision(2)
                      << block.data.price << "\n";
            std::cout << "    Prev Hash   : " << block.previousHash << "\n";
            std::cout << "    Hash        : " << block.hash << "\n";
            std::cout << "    Nonce       : " << block.nonce << "\n";
            std::cout << "    Intact      : "
                      << (block.isIntact() ? "YES" : "TAMPERED") << "\n\n";
        }
        std::cout << std::string(70, '=') << "\n";
    }

    bool saveToFile(const std::string& filename) const
    {
        std::ofstream ofs(filename, std::ios::binary | std::ios::trunc);
        if (!ofs.is_open()) {
            std::cerr << "Cannot open file for writing: " << filename << "\n";
            return false;
        }

        // Write header
        ofs.write(MAGIC_HEADER.data(), MAGIC_HEADER.size());

        int32_t count = (int32_t)chain_.size();
        ofs.write(reinterpret_cast<const char*>(&count), sizeof(count));

        // Pre-allocate buffer for string serialization
        for (const auto& b : chain_) {
            int32_t idx = b.index, nonce = b.nonce;
            ofs.write(reinterpret_cast<const char*>(&idx),   sizeof(idx));
            ofs.write(reinterpret_cast<const char*>(&nonce), sizeof(nonce));

            writeString(ofs, b.timestamp);
            writeString(ofs, b.data.serialize());
            writeString(ofs, b.previousHash);
            writeString(ofs, b.hash);
        }

        writeString(ofs, computeChainChecksum());
        ofs.close();
        return true;
    }

    bool loadFromFile(const std::string& filename)
    {
        std::ifstream ifs(filename, std::ios::binary);
        if (!ifs.is_open()) {
            std::cerr << "Cannot open file: " << filename << "\n";
            return false;
        }

        std::string magic(MAGIC_HEADER.size(), '\0');
        ifs.read(&magic[0], MAGIC_HEADER.size());
        if (magic != MAGIC_HEADER) {
            std::cerr << "Invalid file format\n";
            return false;
        }

        int32_t count = 0;
        ifs.read(reinterpret_cast<char*>(&count), sizeof(count));
        if (count < 1) {
            std::cerr << "Invalid block count\n";
            return false;
        }

        chain_.clear();
        chain_.reserve(count);

        for (int32_t i = 0; i < count; ++i) {
            Block b;
            int32_t idx = 0, nonce = 0;
            ifs.read(reinterpret_cast<char*>(&idx),   sizeof(idx));
            ifs.read(reinterpret_cast<char*>(&nonce), sizeof(nonce));
            b.index        = idx;
            b.nonce        = nonce;
            b.timestamp    = readString(ifs);
            b.data         = EventTicket::deserialize(readString(ifs));
            b.previousHash = readString(ifs);
            b.hash         = readString(ifs);
            chain_.push_back(std::move(b));
        }

        std::string stored_cs = readString(ifs);
        ifs.close();

        if (stored_cs != computeChainChecksum())
            std::cout << "[WARNING] Chain checksum mismatch!\n";

        return true;
    }

    // Optimized transfer with checkpointing and error recovery
    void transferOwnership(std::size_t blockIndex,
                           const std::string& newOwnerName,
                           const std::string& newOwnerID)
    {
        if (blockIndex == 0 || blockIndex >= chain_.size()) {
            std::cout << "  Invalid block index.\n";
            return;
        }

        std::cout << "\n  Transferring ownership of Block #" << blockIndex << "...\n";

        // Store original state for rollback on failure
        std::vector<Block> originalChain = chain_;

        try {
            // Modify and re-mine target block
            chain_[blockIndex].data.ownerName = newOwnerName;
            chain_[blockIndex].data.ownerID   = newOwnerID;
            chain_[blockIndex].previousHash   =
                    (blockIndex > 0) ? chain_[blockIndex-1].hash : std::string(64,'0');
            chain_[blockIndex].nonce = 0;
            chain_[blockIndex].hash  = chain_[blockIndex].calculateHash();
            chain_[blockIndex].mine(difficulty_);

            // Re-mine subsequent blocks
            for (std::size_t i = blockIndex + 1; i < chain_.size(); ++i) {
                chain_[i].previousHash = chain_[i-1].hash;
                chain_[i].nonce = 0;
                chain_[i].hash  = chain_[i].calculateHash();
                chain_[i].mine(difficulty_);
            }

            std::cout << "  Ownership transferred, chain re-mined.\n";

        } catch (const std::exception& e) {
            // Rollback on failure
            chain_ = std::move(originalChain);
            std::cerr << "  Transfer failed: " << e.what() << "\n";
            std::cerr << "  Chain restored to original state.\n";
            throw;
        }
    }

    void demonstrateTampering(std::size_t target_index,
                              const std::string& fake_event_name)
    {
        if (target_index == 0 || target_index >= chain_.size()) {
            std::cout << "Invalid block index.\n";
            return;
        }

        std::cout << "\n" << std::string(70,'-') << "\n";
        std::cout << "  TAMPERING DEMONSTRATION\n";
        std::cout << std::string(70,'-') << "\n\n";

        std::string original = chain_[target_index].data.eventName;
        std::cout << "  Original: \"" << original << "\"\n";
        std::cout << "  Injected: \"" << fake_event_name << "\"\n\n";

        chain_[target_index].data.eventName = fake_event_name;
        std::cout << "  After tampering – validation:\n";
        bool ok = validate(true);
        std::cout << "\n  Result: " << (ok ? "VALID" : "TAMPER DETECTED") << "\n\n";

        chain_[target_index].data.eventName = std::move(original);
        std::cout << "  [Demo finished – chain restored]\n";
        std::cout << std::string(70,'-') << "\n";
    }

    std::size_t size() const noexcept { return chain_.size(); }

private:
    std::vector<Block> chain_;
    int difficulty_;

    Block createGenesisBlock() const
    {
        EventTicket g;
        g.ticketID = g.eventName = "GENESIS BLOCK";
        g.eventDate = "1970-01-01";
        g.venue = "SYSTEM";
        g.ownerName = "SYSTEM";
        g.ownerID = "0";
        g.ticketType = "NONE";
        g.price = 0.0;

        Block genesis(0, g, std::string(64, '0'));
        genesis.mine(difficulty_);
        return genesis;
    }

    std::string computeChainChecksum() const
    {
        std::string combined;
        combined.reserve(chain_.size() * 64);
        for (const auto& b : chain_) combined += b.hash;
        return computeHash(combined);
    }

    static void writeString(std::ofstream& os, const std::string& s)
    {
        uint32_t len = (uint32_t)s.size();
        os.write(reinterpret_cast<const char*>(&len), sizeof(len));
        if (len) os.write(s.data(), len);
    }

    static std::string readString(std::ifstream& is)
    {
        uint32_t len = 0;
        is.read(reinterpret_cast<char*>(&len), sizeof(len));
        std::string s(len, '\0');
        if (len) is.read(&s[0], len);
        return s;
    }
};

#endif // BLOCKCHAIN_H