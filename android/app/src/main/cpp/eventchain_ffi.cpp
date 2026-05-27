// =============================================================================
//  eventchain_ffi.cpp  –  Optimized C shim with same API
//
//  STB INCLUDE ORDER — DO NOT REORDER THESE FOUR BLOCKS.
// =============================================================================

// ── Block 1: stb_image_write (PNG/BMP write, no external deps) ───────────────
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb/stb_image_write.h"

// ── Block 2: stb_image (PNG/JPEG/BMP/WebP read, no external deps) ────────────
#define STB_IMAGE_IMPLEMENTATION
#include "stb/stb_image.h"

// ── Block 3: CImg feature flags ───────────────────────────────────────────────
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
//  FIX: Single definition, no `static` — must match the `extern thread_local`
//  declaration in eventmanager.h so both translation units share the same
//  variable.  The old code had a duplicate `static thread_local` definition
//  below that caused an ODR violation and made setError() write to a shadow
//  variable that eventchain_last_error() never read.
// =============================================================================

thread_local std::string g_last_error;

static void setError(const std::string& msg) {
    g_last_error = msg;
}

// FIX: Single definition of eventchain_last_error — the duplicate at the
// bottom of the old file has been removed.
const char* eventchain_last_error(void) {
    return g_last_error.c_str();
}

// =============================================================================
//  Internal helpers
//  FIX: Moved makeCString up so it is defined before eventchain_raw_extract
//  and eventchain_self_test use it.  In C++ a static function must be defined
//  (or at least declared) before the first call site.
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
//  Diagnostic / raw operations
//  (Placed after helpers so setError and makeCString are already defined.)
// =============================================================================

char* eventchain_raw_extract(EC_Handle handle, const char* stegoPath)
{
    if (!handle || !stegoPath) {
        setError("null argument");
        return nullptr;
    }
    try {
        auto* mgr = static_cast<EventManager*>(handle);
        std::string raw = mgr->rawExtractTicket(stegoPath);
        if (raw.empty()) return nullptr;
        return makeCString(raw);
    } catch (const std::exception& e) {
        setError(e.what());
        return nullptr;
    }
}

char* eventchain_self_test(EC_Handle handle, const char* workDir)
{
    if (!handle || !workDir) {
        setError("null argument");
        return nullptr;
    }
    try {
        auto* mgr = static_cast<EventManager*>(handle);
        std::string report = mgr->selfTest(workDir);
        return makeCString(report);
    } catch (const std::exception& e) {
        setError(e.what());
        return nullptr;
    }
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

// =============================================================================
//  FIX: eventchain_save now checks the bool returned by saveEvent() and
//  propagates the failure to Dart instead of silently swallowing it.
// =============================================================================
int eventchain_save(EC_Handle handle, const char* eventName)
{
    if (!handle || !eventName) {
        setError("null argument");
        return -1;
    }

    try {
        bool ok = static_cast<EventManager*>(handle)->saveEvent(eventName);
        if (!ok) setError("saveEvent returned false");
        return ok ? 0 : -1;
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

// NOTE: eventchain_last_error is defined once near the top of this file.
// The duplicate definition that was here has been removed.