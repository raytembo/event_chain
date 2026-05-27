#include <iostream>
#include <cstdlib>
#include <sys/stat.h>
#include "eventchain_ffi.h"

// Helper to create a test directory
void ensureDir(const char* path) {
#ifdef _WIN32
    _mkdir(path);
#else
    mkdir(path, 0755);
#endif
}

int main() {
    std::cout << "=== EventChain FFI Local Desktop Test ===" << std::endl;

    // 1. Setup
    ensureDir("./test_storage");
    EC_Handle handle = eventchain_create("./test_storage", 2);
    if (!handle) {
        std::cerr << "[FAIL] Create handle: " << eventchain_last_error() << std::endl;
        return 1;
    }
    std::cout << "[INFO] Version: " << eventchain_version() << std::endl;

    // 2. Add a ticket
    const char* eventName = "TestConcert";
    const char* ticketJson = R"({"ticketID":"TCK-001","eventName":"TestConcert","eventDate":"2026-05-27","venue":"Madison Square Garden","ownerName":"Alice","ownerID":"ID-999","ticketType":"VIP","price":150.00})";
    
    if (eventchain_add_ticket(handle, eventName, ticketJson) != 0) {
        std::cerr << "[FAIL] Add ticket: " << eventchain_last_error() << std::endl;
    } else {
        std::cout << "[PASS] Ticket added to blockchain." << std::endl;
    }

    // 3. Generate Cover & Embed (Use specific paths for self-test)
    const char* coverPath = "./test_storage/selftest_cover.png"; // Use path suitable for self-test
    const char* stegoPath = "./test_storage/selftest_stego.png"; // Use path suitable for self-test
    
    if (eventchain_generate_cover(coverPath, 512, 512) != 0) {
        std::cerr << "[FAIL] Generate cover for self-test: " << eventchain_last_error() << std::endl;
        eventchain_destroy(handle);
        return 1;
    }
    std::cout << "[INFO] Generated cover for self-test: " << coverPath << std::endl;

    // --- Run Self-Test BEFORE attempting main flow extract ---
    std::cout << "\n--- Running Steganography Self-Test ---" << std::endl;
    char* selfTestReport = eventchain_self_test(handle, "./test_storage"); // Pass the directory
    if (selfTestReport) {
        std::cout << selfTestReport << std::endl;
        eventchain_free_string(selfTestReport);
    } else {
        std::cerr << "[ERROR] Self-test returned null: " << eventchain_last_error() << std::endl;
    }
    std::cout << "--- Self-Test Complete ---\n" << std::endl;

    // --- Now proceed with original test flow ---
    const char* coverPathMain = "./test_storage/cover.png";
    const char* stegoPathMain = "./test_storage/stego.png";
    
    eventchain_generate_cover(coverPathMain, 512, 512); // Generate cover for main flow
    
    if (eventchain_embed_ticket(handle, eventName, 1, coverPathMain, stegoPathMain) != 0) {
        std::cerr << "[FAIL] Embed ticket: " << eventchain_last_error() << std::endl;
    } else {
        std::cout << "[PASS] Ticket embedded into image." << std::endl;
    }

    // 4. Extract and Verify (Original flow)
    int verified = eventchain_extract_verify(handle, stegoPathMain, eventName, 1);
    if (verified == 1) {
        std::cout << "[PASS] Ticket verified successfully against blockchain!" << std::endl;
    } else {
        std::cerr << "[FAIL] Ticket verification failed: " << eventchain_last_error() << std::endl;
    }

    // 5. Raw Extract Test (Diagnostic)
    char* raw = eventchain_raw_extract(handle, stegoPathMain);
    if (raw) {
        std::cout << "[INFO] Raw extracted payload: " << raw << std::endl;
        eventchain_free_string(raw);
    } else {
        std::cerr << "[WARN] Raw extract returned null: " << eventchain_last_error() << std::endl;
    }

    // 6. Cleanup
    eventchain_destroy(handle);
    std::cout << "=== Test Complete ===" << std::endl;
    return 0;
}