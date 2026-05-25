// =============================================================================
//  eventchain_ffi.cpp  –  Optimized C shim with same API
//
//  STB INCLUDE ORDER — DO NOT REORDER THESE FOUR BLOCKS.
//
//  CImg.h is pulled in transitively by:
//    eventmanager.h  →  steganography.h  →  CImg.h
//
//  CImg tests #ifdef cimg_use_stb at the very top of its header to decide
//  whether to delegate load() to stb_image.  That define MUST be visible
//  before the first token of CImg.h is processed, which means it must appear
//  before the #include "eventmanager.h" line below.
//
//  Likewise, STB_IMAGE_IMPLEMENTATION and STB_IMAGE_WRITE_IMPLEMENTATION must
//  each be defined in exactly one translation unit before their respective
//  headers are included anywhere in the whole compilation unit — including
//  headers pulled in transitively.  Putting both here, before every other
//  include, guarantees that invariant.
//
//  Why stb_image is needed:
//    CImg's load_png() requires libpng (cimg_use_png) which is not linked in
//    the Android NDK build.  Without cimg_use_stb, any call to
//    DCTSteganography::embed() with a PNG cover throws a CImgIOException that
//    is silently caught, returning false — the root cause of the
//    "Could not generate your ticket image" failure.
// =============================================================================

// ── Block 1: stb_image_write (PNG/BMP write, no external deps) ───────────────
// Must come first because steganography.h forward-declares stbi_write_png.
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb/stb_image_write.h"

// ── Block 2: stb_image (PNG/JPEG/BMP/WebP read, no external deps) ────────────
// Provides the read back-end that cimg_use_stb wires into CImg::load().
#define STB_IMAGE_IMPLEMENTATION
#include "stb/stb_image.h"

// ── Block 3: CImg feature flags ───────────────────────────────────────────────
// cimg_use_stb  — redirect CImg's load()/save() through stb for all formats
//                 that stb supports (PNG, JPEG, BMP, TGA, HDR, PNM …).
//                 Without this, CImg falls back to load_png() which needs
//                 libpng; on Android NDK that throws CImgIOException.
// cimg_display  — must be 0 on headless/mobile targets; no display server.
#define cimg_use_stb  1
#define cimg_display  0

// ── Block 4: project headers (CImg.h arrives transitively here) ───────────────
#include "eventchain_ffi.h"
#include "eventmanager.h"

// ── Standard library ──────────────────────────────────────────────────────────
#include <cstring>
#include <cstdlib>
#include <stdexcept>
#include <sstream>
#include <iomanip>
#include <string>

// =============================================================================
//  Per-thread last-error store
// =============================================================================

static thread_local std::string g_last_error;

static void setError(const std::string& msg) {
    g_last_error = msg;
}

// =============================================================================
//  Internal helpers
// =============================================================================

// Allocate a heap copy of s for Dart to receive and later free via
// eventchain_free_string().  Returns nullptr on allocation failure.
static char* makeCString(const std::string& s) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (p) std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

// Escape a UTF-8 string for embedding inside a JSON string literal.
static std::string jsonEscape(const std::string& s) {
    std::ostringstream out;
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\n': out << "\\n";  break;
            case '\r': out << "\\r";  break;
            case '\t': out << "\\t";  break;
            default:
                if (c < 0x20) {
                    out << "\\u" << std::hex << std::setw(4)
                        << std::setfill('0') << static_cast<int>(c) << std::dec;
                } else {
                    out << c;
                }
        }
    }
    return out.str();
}

// Serialize one EventTicket to a JSON object string.
static std::string ticketToJson(const EventTicket& t) {
    std::ostringstream j;
    j << "{"
      << "\"ticketID\":\""   << jsonEscape(t.ticketID)   << "\","
      << "\"eventName\":\""  << jsonEscape(t.eventName)  << "\","
      << "\"eventDate\":\""  << jsonEscape(t.eventDate)  << "\","
      << "\"venue\":\""      << jsonEscape(t.venue)      << "\","
      << "\"ownerName\":\""  << jsonEscape(t.ownerName)  << "\","
      << "\"ownerID\":\""    << jsonEscape(t.ownerID)    << "\","
      << "\"ticketType\":\"" << jsonEscape(t.ticketType) << "\","
      << "\"price\":"        << std::fixed << std::setprecision(2)
      << t.price
      << "}";
    return j.str();
}

// Extract the string value for a JSON key of the form "key":"value".
static std::string jsonGet(const std::string& json, const std::string& key) {
    const std::string needle = "\"" + key + "\":\"";
    std::size_t pos = json.find(needle);
    if (pos == std::string::npos) return "";
    pos += needle.size();
    std::size_t end = json.find('"', pos);
    if (end == std::string::npos) return "";
    return json.substr(pos, end - pos);
}

// Extract the numeric value for a JSON key of the form "key":number.
static double jsonGetDouble(const std::string& json, const std::string& key) {
    const std::string needle = "\"" + key + "\":";
    std::size_t pos = json.find(needle);
    if (pos == std::string::npos) return 0.0;
    pos += needle.size();
    try { return std::stod(json.substr(pos)); } catch (...) { return 0.0; }
}

// =============================================================================
//  Lifecycle
// =============================================================================

EC_Handle eventchain_create(const char* storageFolder, int difficulty)
{
    try {
        std::string folder = storageFolder ? storageFolder : "";
        int diff = (difficulty >= 1 && difficulty <= 5) ? difficulty : 2;
        return new EventManager(diff, folder);
    } catch (const std::exception& e) {
        setError(e.what());
        return nullptr;
    }
}

void eventchain_destroy(EC_Handle handle)
{
    if (handle) delete static_cast<EventManager*>(handle);
}

// =============================================================================
//  String memory management
// =============================================================================

void eventchain_free_string(char* ptr)
{
    std::free(ptr);
}

// =============================================================================
//  Blockchain operations
// =============================================================================

int eventchain_add_ticket(EC_Handle   handle,
                          const char* eventName,
                          const char* ticketJson)
{
    if (!handle || !eventName || !ticketJson) {
        setError("null argument");
        return -1;
    }

    try {
        auto* mgr = static_cast<EventManager*>(handle);
        const std::string js = ticketJson;

        EventTicket t;
        t.ticketID   = jsonGet(js, "ticketID");
        t.eventName  = jsonGet(js, "eventName");
        t.eventDate  = jsonGet(js, "eventDate");
        t.venue      = jsonGet(js, "venue");
        t.ownerName  = jsonGet(js, "ownerName");
        t.ownerID    = jsonGet(js, "ownerID");
        t.ticketType = jsonGet(js, "ticketType");
        t.price      = jsonGetDouble(js, "price");

        if (t.ticketID.empty() || t.eventName.empty()) {
            setError("ticketID and eventName are required");
            return -1;
        }

        mgr->addTicketToEvent(std::string(eventName), t);
        return 0;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

int eventchain_validate(EC_Handle handle, const char* eventName)
{
    if (!handle || !eventName) {
        setError("null argument");
        return -1;
    }

    try {
        auto* mgr = static_cast<EventManager*>(handle);
        return mgr->validateEvent(std::string(eventName)) ? 1 : 0;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

int eventchain_get_size(EC_Handle handle, const char* eventName)
{
    if (!handle || !eventName) {
        setError("null argument");
        return -1;
    }

    try {
        return static_cast<EventManager*>(handle)->getEventSize(eventName);
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

char* eventchain_get_chain_json(EC_Handle handle, const char* eventName)
{
    if (!handle || !eventName) {
        setError("null argument");
        return nullptr;
    }

    try {
        auto* mgr = static_cast<EventManager*>(handle);
        const int sz = mgr->getEventSize(eventName);
        if (sz < 0) {
            setError("event not found");
            return nullptr;
        }

        std::ostringstream out;
        out << "[";
        for (int i = 0; i < sz; ++i) {
            if (i > 0) out << ",";
            const EventTicket& t =
                mgr->getChain(eventName).getTicket(static_cast<std::size_t>(i));
            out << "{\"index\":" << i << ","
                << "\"ticket\":" << ticketToJson(t) << "}";
        }
        out << "]";

        return makeCString(out.str());
    } catch (const std::exception& e) {
        setError(e.what());
        return nullptr;
    }
}

int eventchain_transfer_ownership(EC_Handle   handle,
                                   const char* eventName,
                                   int         blockIndex,
                                   const char* newOwnerName,
                                   const char* newOwnerID)
{
    if (!handle || !eventName || !newOwnerName || !newOwnerID) {
        setError("null argument");
        return -1;
    }

    try {
        static_cast<EventManager*>(handle)->transferTicketOwnership(
            eventName, blockIndex, newOwnerName, newOwnerID);
        return 0;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

char* eventchain_get_ticket_json(EC_Handle   handle,
                                  const char* eventName,
                                  int         blockIndex)
{
    if (!handle || !eventName) {
        setError("null argument");
        return nullptr;
    }

    try {
        auto* mgr = static_cast<EventManager*>(handle);
        const EventTicket& t =
            mgr->getChain(eventName).getTicket(static_cast<std::size_t>(blockIndex));
        return makeCString(ticketToJson(t));
    } catch (const std::exception& e) {
        setError(e.what());
        return nullptr;
    }
}

int eventchain_save(EC_Handle handle, const char* eventName)
{
    if (!handle || !eventName) {
        setError("null argument");
        return -1;
    }

    try {
        static_cast<EventManager*>(handle)->saveEvent(eventName);
        return 0;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

int eventchain_load(EC_Handle handle, const char* eventName)
{
    if (!handle || !eventName) {
        setError("null argument");
        return -1;
    }

    try {
        static_cast<EventManager*>(handle)->loadEvent(eventName);
        return 0;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

char* eventchain_list_events(EC_Handle handle)
{
    if (!handle) {
        setError("null handle");
        return nullptr;
    }

    try {
        auto* mgr = static_cast<EventManager*>(handle);
        const auto& names = mgr->getEventNames();

        std::ostringstream out;
        out << "[";
        bool first = true;
        for (const auto& n : names) {
            if (!first) out << ",";
            out << "\"" << jsonEscape(n) << "\"";
            first = false;
        }
        out << "]";

        return makeCString(out.str());
    } catch (const std::exception& e) {
        setError(e.what());
        return nullptr;
    }
}

// =============================================================================
//  Steganography operations
// =============================================================================

int eventchain_generate_cover(const char* outputPath, int width, int height)
{
    if (!outputPath) {
        setError("null path");
        return -1;
    }

    try {
        return DCTSteganography::generateCover(outputPath, width, height) ? 0 : -1;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

int eventchain_embed_ticket(EC_Handle   handle,
                             const char* eventName,
                             int         blockIndex,
                             const char* coverPath,
                             const char* stegoPath)
{
    if (!handle || !eventName || !stegoPath) {
        setError("null argument");
        return -1;
    }

    try {
        const std::string cover = (coverPath && coverPath[0]) ? coverPath : "";
        const bool ok = static_cast<EventManager*>(handle)
                ->embedTicketInImage(eventName, blockIndex, cover, stegoPath);
        if (!ok) setError(g_last_error.empty()
                          ? "embedTicketInImage returned false"
                          : g_last_error);
        return ok ? 0 : -1;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

int eventchain_extract_verify(EC_Handle   handle,
                               const char* stegoPath,
                               const char* eventName,
                               int         blockIndex)
{
    if (!handle || !stegoPath || !eventName) {
        setError("null argument");
        return -1;
    }

    try {
        const bool ok = static_cast<EventManager*>(handle)
                ->extractAndVerifyTicket(stegoPath, eventName, blockIndex);
        return ok ? 1 : 0;
    } catch (const std::exception& e) {
        setError(e.what());
        return -1;
    }
}

int eventchain_stego_capacity(int imageWidth, int imageHeight)
{
    return static_cast<int>(DCTSteganography::capacity(imageWidth, imageHeight));
}

// =============================================================================
//  Utility
// =============================================================================

const char* eventchain_version(void) {
    return "EventChain-1.0.0-optimized";
}

const char* eventchain_last_error(void) {
    return g_last_error.c_str();
}