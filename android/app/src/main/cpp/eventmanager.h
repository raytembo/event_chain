// =============================================================================
//  eventmanager.h  –  UPDATED: all FFI-required methods added
//
//  Fixes applied:
//    1. Added public getChain(eventName)     → required by eventchain_ffi.cpp
//    2. Added public getEventNames()         → required by eventchain_ffi.cpp
//    3. Fixed generateCover() call signature → 3 args (path, width, height)
//    4. <vector> include confirmed present
// =============================================================================

#ifndef EVENTMANAGER_H
#define EVENTMANAGER_H

#include <map>
#include <vector>
#include <string>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <sys/stat.h>

#include "config.h"
#include "blockchain.h"
#include "ticket.h"
#include "fibonacci_encryption.h"
#include "./stego/steganography.h"

// helper: does a file exist?
static inline bool fileExists(const std::string& path) {
    std::ifstream f(path);
    return f.good();
}

// helper: does a directory exist?
static inline bool dirExists(const std::string& path) {
    struct stat st;
    return (stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode));
}

// helper: create directory (cross-platform)
static inline void mkdirP(const std::string& path) {
#ifdef _WIN32
    _mkdir(path.c_str());
#else
    mkdir(path.c_str(), 0755);
#endif
}

// =============================================================================
class EventManager
{
public:
    explicit EventManager(int difficulty = MINE_DIFFICULTY,
            const std::string& storageFolder = "")
            : mDifficulty(difficulty), mStorageFolder(storageFolder) {}

    // ── core blockchain methods ───────────────────────────────────────────────

    void addTicketToEvent(const std::string& eventName, EventTicket& ticket)
    {
        Blockchain& chain = getOrCreateChain(eventName);

        std::string plain     = ticket.serialize();
        std::string encrypted = fibonacciEncryptDecrypt(plain);
        std::cout << "  [Fibonacci] Payload encrypted (ready for DCT steganography).\n";

        chain.addTicket(ticket);
        saveEvent(eventName);
    }

    void viewEvent(const std::string& eventName)
    { getOrCreateChain(eventName).print(); }

    bool validateEvent(const std::string& eventName)
    { return getOrCreateChain(eventName).validate(true); }

    void saveEvent(const std::string& eventName)
    {
        auto it = mEventChains.find(eventName);
        if (it == mEventChains.end()) {
            std::cout << "  Event '" << eventName << "' not loaded yet.\n";
            return;
        }
        std::string fullPath = getFullPath(eventName);
        it->second.saveToFile(fullPath);
        std::cout << "  Saved to " << fullPath << "\n";
    }

    void loadEvent(const std::string& eventName)
    {
        std::string fullPath = getFullPath(eventName);
        std::ifstream test(fullPath, std::ios::binary);
        if (!test.is_open()) {
            std::cout << "  Cannot open file: " << fullPath << "\n";
            return;
        }
        test.close();
        Blockchain chain(mDifficulty);
        if (chain.loadFromFile(fullPath)) {
            mEventChains[eventName] = std::move(chain);
            std::cout << "  Loaded chain for '" << eventName
                      << "' from " << fullPath << "\n";
        }
    }

    void listEvents() const
    {
        if (mEventChains.empty()) {
            std::cout << "  No events loaded yet.\n"; return;
        }
        std::cout << "\n  Loaded events:\n";
        for (const auto& p : mEventChains)
            std::cout << "    • " << p.first
                      << " (" << p.second.size() << " blocks)\n";
    }

    void transferTicketOwnership(const std::string& eventName, int blockIdx,
            const std::string& newOwnerName,
            const std::string& newOwnerID)
    {
        Blockchain& chain = getOrCreateChain(eventName);
        chain.transferOwnership((std::size_t)blockIdx, newOwnerName, newOwnerID);
        saveEvent(eventName);
    }

    bool exportEvent(const std::string& eventName, const std::string& target)
    {
        auto it = mEventChains.find(eventName);
        if (it == mEventChains.end()) {
            std::cout << "  Event not loaded.\n"; return false;
        }
        bool ok = it->second.saveToFile(target);
        if (ok) std::cout << "  Exported as: " << target << "\n";
        return ok;
    }

    bool importEvent(const std::string& srcFile, const std::string& targetEvent)
    {
        Blockchain chain(mDifficulty);
        if (!chain.loadFromFile(srcFile)) {
            std::cout << "  Import failed.\n"; return false;
        }
        mEventChains[targetEvent] = std::move(chain);
        std::string full = getFullPath(targetEvent);
        mEventChains[targetEvent].saveToFile(full);
        std::cout << "  Imported as '" << targetEvent
                  << "', saved to " << full << "\n";
        return true;
    }

    void demonstrateTamperingForEvent(const std::string& eventName,
            int targetIdx,
            const std::string& fakeEventName)
    {
        Blockchain& chain = getOrCreateChain(eventName);
        if ((std::size_t)targetIdx >= chain.size()) {
            std::cout << "  Invalid block index.\n"; return;
        }
        chain.demonstrateTampering((std::size_t)targetIdx, fakeEventName);
    }

    int getEventSize(const std::string& eventName)
    { return (int)getOrCreateChain(eventName).size(); }

    // ── FIX 1: getChain() — required by eventchain_ffi.cpp ───────────────────
    // Exposes the Blockchain for a given event publicly.
    // Delegates to the private getOrCreateChain() which handles lazy-loading.
    Blockchain& getChain(const std::string& eventName)
    {
        return getOrCreateChain(eventName);
    }

    // ── FIX 2: getEventNames() — required by eventchain_ffi.cpp ──────────────
    // Returns a list of all currently loaded event names.
    // Used by eventchain_list_events() to build the JSON array.
    std::vector<std::string> getEventNames() const
    {
        std::vector<std::string> names;
        names.reserve(mEventChains.size());
        for (const auto& p : mEventChains)
            names.push_back(p.first);
        return names;
    }

    // ── steganography methods ─────────────────────────────────────────────────

    // -------------------------------------------------------------------
    // embedTicketInImage
    //   Encodes the ticket at blockIdx (>= 1, genesis is 0) from the
    //   event chain into a stego BMP image.
    //
    //   coverPath : path to an existing BMP cover image, OR empty string
    //               to auto-generate a synthetic 512×512 cover.
    //   stegoPath : where to write the output stego BMP.
    //
    //   The payload embedded is:
    //     Fibonacci-XOR( ticket.serialize() )
    //   so only someone with knowledge of the Fibonacci key can decode it.
    // -------------------------------------------------------------------
    bool embedTicketInImage(const std::string& eventName,
            int                blockIdx,
            const std::string& coverPath,
            const std::string& stegoPath)
    {
        Blockchain& chain = getOrCreateChain(eventName);
        if (blockIdx <= 0 || blockIdx >= (int)chain.size()) {
            std::cout << "  Invalid block index " << blockIdx << "\n";
            return false;
        }

        const EventTicket& ticket = chain.getTicket((std::size_t)blockIdx);

        std::string plain     = ticket.serialize();
        std::string encrypted = fibonacciEncryptDecrypt(plain);
        std::size_t needed    = encrypted.size();

        // ── prepare cover ──────────────────────────────────────────────
        std::string activeCover = coverPath;
        if (activeCover.empty() || !fileExists(activeCover)) {
            std::string genPath = stegoPath + "_cover.png";
            if (!DCTSteganography::generateCover(genPath, 512, 512)) return false;
            activeCover = genPath;
        }

        // ── embed ──────────────────────────────────────────────────────
        bool ok = DCTSteganography::embed(activeCover, stegoPath, encrypted);
        if (ok) {
            std::cout << "  [Stego] Ticket #" << blockIdx
                      << " from event '" << eventName
                      << "' embedded in: " << stegoPath << "\n";
            std::cout << "  [Stego] Payload: " << needed
                      << " bytes  (Fibonacci-encrypted)\n";
        }
        return ok;
    }

    // -------------------------------------------------------------------
    // extractAndVerifyTicket
    //   Reads the hidden bytes from stegoPath, Fibonacci-decrypts them,
    //   deserializes the ticket, then compares every field against the
    //   on-chain block at eventName / blockIdx.
    //   Returns true if all fields match (ticket is authentic).
    // -------------------------------------------------------------------
    bool extractAndVerifyTicket(const std::string& stegoPath,
            const std::string& eventName,
            int                blockIdx)
    {
        std::string extracted = DCTSteganography::extract(stegoPath);
        if (extracted.empty()) {
            std::cout << "  [Stego] Extraction failed or nothing hidden.\n";
            return false;
        }

        std::string plaintext = fibonacciEncryptDecrypt(extracted);

        EventTicket stegTicket;
        try {
            stegTicket = EventTicket::deserialize(plaintext);
        } catch (...) {
            std::cout << "  [Stego] Deserialization failed (corrupted stego?).\n";
            return false;
        }

        Blockchain& chain = getOrCreateChain(eventName);
        if (blockIdx <= 0 || blockIdx >= (int)chain.size()) {
            std::cout << "  [Stego] Block index out of range.\n";
            return false;
        }
        const EventTicket& chainTicket = chain.getTicket((std::size_t)blockIdx);

        bool match = (stegTicket.ticketID   == chainTicket.ticketID   &&
                stegTicket.eventName  == chainTicket.eventName  &&
                stegTicket.eventDate  == chainTicket.eventDate  &&
                stegTicket.venue      == chainTicket.venue      &&
                stegTicket.ownerName  == chainTicket.ownerName  &&
                stegTicket.ownerID    == chainTicket.ownerID    &&
                stegTicket.ticketType == chainTicket.ticketType &&
                std::abs(stegTicket.price - chainTicket.price) < 0.001);

        std::cout << "\n  ── Ticket Verification Report ──────────────────\n";
        printField("Ticket ID",   stegTicket.ticketID,   chainTicket.ticketID);
        printField("Event",       stegTicket.eventName,  chainTicket.eventName);
        printField("Date",        stegTicket.eventDate,  chainTicket.eventDate);
        printField("Venue",       stegTicket.venue,      chainTicket.venue);
        printField("Owner",       stegTicket.ownerName,  chainTicket.ownerName);
        printField("Owner ID",    stegTicket.ownerID,    chainTicket.ownerID);
        printField("Type",        stegTicket.ticketType, chainTicket.ticketType);
        std::cout << (match ? "  RESULT: AUTHENTIC ✓\n" : "  RESULT: MISMATCH ✗\n");
        std::cout << "  ────────────────────────────────────────────────\n";
        return match;
    }

    // -------------------------------------------------------------------
    // embedAllTickets
    //   Batch-embeds every non-genesis block in the event chain.
    //   If coversFolder contains "cover_N.png" for block N, it is used;
    //   otherwise a synthetic PNG cover is generated.
    //   Stego images are written to stegoFolder as "stego_N.png".
    // -------------------------------------------------------------------
    void embedAllTickets(const std::string& eventName,
            const std::string& coversFolder,
            const std::string& stegoFolder)
    {
        mkdirP(stegoFolder);
        Blockchain& chain = getOrCreateChain(eventName);
        int count = (int)chain.size();
        std::cout << "\n  Embedding " << count - 1 << " ticket(s)...\n";

        for (int i = 1; i < count; ++i) {
            std::string cover = coversFolder + "/cover_" + std::to_string(i) + ".png";
            std::string stego = stegoFolder  + "/stego_" + std::to_string(i) + ".png";
            embedTicketInImage(eventName, i, cover, stego);
        }
        std::cout << "  Done. Stego images in: " << stegoFolder << "/\n";
    }

private:
    std::map<std::string, Blockchain> mEventChains;
    int mDifficulty;
    std::string mStorageFolder;

    // ── path helper ───────────────────────────────────────────────────────────
    std::string getFullPath(const std::string& eventName) const
    {
        if (mStorageFolder.empty()) return eventName + FILE_EXT;
        std::string f = mStorageFolder;
        if (!f.empty() && f.back() != '/' && f.back() != '\\') f += '/';
        return f + eventName + FILE_EXT;
    }

    // ── lazy-load / create chain ──────────────────────────────────────────────
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
                std::cout << "  Loaded existing chain for '" << eventName << "'\n";
        } else {
            std::cout << "  Creating NEW event blockchain: " << eventName << "\n";
            chain.saveToFile(fullPath);
        }
        mEventChains[eventName] = std::move(chain);
        return mEventChains[eventName];
    }

    // ── verification print helper ─────────────────────────────────────────────
    static void printField(const std::string& label,
            const std::string& extracted,
            const std::string& onchain)
    {
        bool ok = (extracted == onchain);
        std::cout << "  " << std::left << std::setw(12) << label
                  << ": " << (ok ? "[OK] " : "[!!] ")
                  << extracted;
        if (!ok) std::cout << "  (chain: " << onchain << ")";
        std::cout << "\n";
    }
};

#endif // EVENTMANAGER_H