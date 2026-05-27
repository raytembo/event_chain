// eventmanager.h  –  DIAGNOSTIC EDITION

#ifndef EVENTMANAGER_H
#define EVENTMANAGER_H

#include <map>
#include <vector>
#include <string>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <sys/stat.h>
#include <cctype>
#include <sstream>

#include "config.h"
#include "blockchain.h"
#include "ticket.h"
#include "fibonacci_encryption.h"
#include "./stego/steganography.h"

static inline bool fileExists(const std::string& path) {
    std::ifstream f(path); return f.good();
}
static inline bool dirExists(const std::string& path) {
    struct stat st; return (stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode));
}
static inline void mkdirP(const std::string& path) {
#ifdef _WIN32
    _mkdir(path.c_str());
#else
    mkdir(path.c_str(), 0755);
#endif
}

static inline std::string sanitizeFilename(const std::string& name) {
    std::size_t start = 0;
    while (start < name.size() && std::isspace(static_cast<unsigned char>(name[start]))) ++start;
    std::size_t end = name.size();
    while (end > start && std::isspace(static_cast<unsigned char>(name[end - 1]))) --end;
    std::string trimmed = name.substr(start, end - start);
    std::string out; out.reserve(trimmed.size());
    for (unsigned char c : trimmed) {
        if (std::isalnum(c) || c == '_' || c == '-') out += static_cast<char>(c);
        else out += '_';
    }
    return out.empty() ? "unnamed_event" : out;
}

// Forward-declared so eventmanager.cpp (or ffi) can set it.
extern thread_local std::string g_last_error;
static inline void setLastError(const std::string& msg) { g_last_error = msg; }

class EventManager
{
public:
    explicit EventManager(int difficulty = MINE_DIFFICULTY,
            const std::string& storageFolder = "")
            : mDifficulty(difficulty), mStorageFolder(storageFolder) {}

    void addTicketToEvent(const std::string& eventName, EventTicket& ticket)
    {
        Blockchain& chain = getOrCreateChain(eventName);
        chain.addTicket(ticket);
        if (!saveEvent(eventName)) {
            throw std::runtime_error("Failed to save event chain after adding ticket");
        }
    }

    bool validateEvent(const std::string& eventName)
    { return getOrCreateChain(eventName).validate(true); }

    bool saveEvent(const std::string& eventName)
    {
        auto it = mEventChains.find(eventName);
        if (it == mEventChains.end()) { setLastError("Event not loaded"); return false; }
        std::string fullPath = getFullPath(eventName);
        bool ok = it->second.saveToFile(fullPath);
        if (!ok) setLastError("saveToFile returned false for " + fullPath);
        return ok;
    }

    void loadEvent(const std::string& eventName)
    {
        std::string fullPath = getFullPath(eventName);
        std::ifstream test(fullPath, std::ios::binary);
        if (!test.is_open()) { setLastError("Cannot open: " + fullPath); return; }
        test.close();
        Blockchain chain(mDifficulty);
        if (chain.loadFromFile(fullPath)) {
            mEventChains[eventName] = std::move(chain);
        } else {
            setLastError("loadFromFile failed: " + fullPath);
        }
    }

    void listEvents() const
    {
        if (mEventChains.empty()) std::cout << "  No events loaded.\n";
        else for (const auto& p : mEventChains)
            std::cout << "    " << p.first << " (" << p.second.size() << " blocks)\n";
    }

    void transferTicketOwnership(const std::string& eventName, int blockIdx,
            const std::string& newOwnerName, const std::string& newOwnerID)
    {
        Blockchain& chain = getOrCreateChain(eventName);
        chain.transferOwnership((std::size_t)blockIdx, newOwnerName, newOwnerID);
        if (!saveEvent(eventName))
            throw std::runtime_error("Failed to save after ownership transfer");
    }

    int getEventSize(const std::string& eventName)
    { return (int)getOrCreateChain(eventName).size(); }

    Blockchain& getChain(const std::string& eventName)
    { return getOrCreateChain(eventName); }

    std::vector<std::string> getEventNames() const
    {
        std::vector<std::string> names;
        for (const auto& p : mEventChains) names.push_back(p.first);
        return names;
    }

    // ── Steganography ───────────────────────────────────────────────────────

    bool embedTicketInImage(const std::string& eventName,
            int blockIdx,
            const std::string& coverPath,
            const std::string& stegoPath)
    {
        Blockchain& chain = getOrCreateChain(eventName);
        if (blockIdx <= 0 || blockIdx >= (int)chain.size()) {
            setLastError("Invalid block index " + std::to_string(blockIdx) +
                         " for chain size " + std::to_string(chain.size()));
            return false;
        }

        const EventTicket& ticket = chain.getTicket((std::size_t)blockIdx);
        std::string plain = ticket.serialize();
        std::string encrypted = fibonacciEncryptDecrypt(plain);
        std::size_t needed = encrypted.size();

        std::string activeCover = coverPath;
        if (activeCover.empty() || !fileExists(activeCover)) {
            std::string genPath = stegoPath + "_cover.png";
            if (!DCTSteganography::generateCover(genPath, 512, 512)) {
                setLastError("Cover generation failed");
                return false;
            }
            activeCover = genPath;
        }

        std::cout << "  [Embed] event=" << eventName << " block=" << blockIdx
                  << " payload=" << needed << "B cover=" << activeCover << "\n";

        bool ok = DCTSteganography::embed(activeCover, stegoPath, encrypted);
        if (!ok) {
            if (g_last_error.empty()) setLastError("DCTSteganography::embed returned false");
            return false;
        }
        std::cout << "  [Embed] SUCCESS -> " << stegoPath << "\n";
        return true;
    }

    // ── DIAGNOSTIC: extract WITHOUT chain verification ───────────────────────
    std::string rawExtractTicket(const std::string& stegoPath)
    {
        auto r = DCTSteganography::diagnosticExtract(stegoPath);
        if (!r.success) {
            setLastError("rawExtract: " + r.error);
            return "";
        }
        std::string plaintext = fibonacciEncryptDecrypt(r.payload);
        std::cout << "  [RawExtract] Decrypted payload: " << plaintext << "\n";
        return plaintext;
    }

    bool extractAndVerifyTicket(const std::string& stegoPath,
            const std::string& eventName,
            int blockIdx)
    {
        std::cout << "  [Verify] stego=" << stegoPath
                  << " event=" << eventName << " block=" << blockIdx << "\n";

        // 1. Extract
        auto ex = DCTSteganography::diagnosticExtract(stegoPath);
        if (!ex.success) {
            setLastError("Extraction failed: " + ex.error);
            std::cout << "  [Verify] FAIL: " << ex.error << "\n";
            return false;
        }

        // 2. Decrypt
        std::string plaintext = fibonacciEncryptDecrypt(ex.payload);
        std::cout << "  [Verify] Decrypted: " << plaintext << "\n";

        // 3. Deserialize
        EventTicket stegTicket;
        try { stegTicket = EventTicket::deserialize(plaintext); }
        catch (...) {
            setLastError("Ticket deserialization failed");
            std::cout << "  [Verify] FAIL: deserialization error\n";
            return false;
        }

        // 4. Chain lookup
        Blockchain& chain = getOrCreateChain(eventName);
        if (blockIdx <= 0 || blockIdx >= (int)chain.size()) {
            setLastError("Block index out of range: " + std::to_string(blockIdx));
            return false;
        }
        const EventTicket& chainTicket = chain.getTicket((std::size_t)blockIdx);

        // 5. Field-by-field comparison with detailed logging
        bool match = true;
        auto check = [&](const char* label, const std::string& a, const std::string& b) {
            bool ok = (a == b);
            if (!ok) {
                match = false;
                std::cout << "  [Verify-FIELD] " << label << " MISMATCH\n";
                std::cout << "    stego:  '" << a << "'\n";
                std::cout << "    chain:  '" << b << "'\n";
            }
            return ok;
        };

        check("ticketID",   stegTicket.ticketID,   chainTicket.ticketID);
        check("eventName",  stegTicket.eventName,  chainTicket.eventName);
        check("eventDate",  stegTicket.eventDate,  chainTicket.eventDate);
        check("venue",      stegTicket.venue,      chainTicket.venue);
        check("ownerName",  stegTicket.ownerName,  chainTicket.ownerName);
        check("ownerID",    stegTicket.ownerID,    chainTicket.ownerID);
        check("ticketType", stegTicket.ticketType, chainTicket.ticketType);

        bool priceOk = std::abs(stegTicket.price - chainTicket.price) < 0.001;
        if (!priceOk) {
            match = false;
            std::cout << "  [Verify-FIELD] price MISMATCH\n";
            std::cout << "    stego:  " << stegTicket.price << "\n";
            std::cout << "    chain:  " << chainTicket.price << "\n";
        }

        std::cout << "  [Verify] RESULT: " << (match ? "AUTHENTIC" : "TAMPERED") << "\n";
        if (!match) setLastError("Ticket field mismatch");
        return match;
    }

    // ── Self-test (no chain needed) ─────────────────────────────────────────
    std::string selfTest(const std::string& workDir)
    {
        std::string cover = workDir + "/selftest_cover.png";
        std::string stego = workDir + "/selftest_stego.png";
        std::string payload = "TestPayload|Event|2026-01-01|Venue|Owner|ID123|VIP|99.99";
        return DCTSteganography::selfTestRoundtrip(cover, stego, payload);
    }

private:
    std::map<std::string, Blockchain> mEventChains;
    int mDifficulty;
    std::string mStorageFolder;

    std::string getFullPath(const std::string& eventName) const
    {
        std::string safeName = sanitizeFilename(eventName);
        if (mStorageFolder.empty()) return safeName + FILE_EXT;
        std::string f = mStorageFolder;
        if (!f.empty() && f.back() != '/' && f.back() != '\\') f += '/';
        return f + safeName + FILE_EXT;
    }

    Blockchain& getOrCreateChain(const std::string& eventName)
    {
        auto it = mEventChains.find(eventName);
        if (it != mEventChains.end()) return it->second;

        std::string fullPath = getFullPath(eventName);
        Blockchain chain(mDifficulty);
        std::ifstream test(fullPath, std::ios::binary);
        if (test.is_open()) {
            test.close();
            if (chain.loadFromFile(fullPath))
                std::cout << "  Loaded existing chain: " << eventName << "\n";
        } else {
            chain.saveToFile(fullPath);
        }
        mEventChains[eventName] = std::move(chain);
        return mEventChains[eventName];
    }
};

#endif // EVENTMANAGER_H