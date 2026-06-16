# EventChain

**Secure Event Ticket Management with Blockchain + Steganography**

[![Flutter Version](https://img.shields.io/badge/Flutter-3.22-blue.svg)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.4-blue.svg)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20API%2023+-green.svg)](https://android.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Overview

EventChain is a cross-platform mobile event ticketing system that eliminates the structural security vulnerabilities of traditional QR code-based tickets by combining **DCT-QIM image steganography**, **Fibonacci XOR stream cipher encryption**, and a **private proof-of-work blockchain** into a single offline-verifiable ticket artifact.

Unlike QR codes — which are trivially cloned via screenshot, require constant internet connectivity for verification, expose plaintext data, and provide no issuer authentication — EventChain embeds encrypted ticket data invisibly within event poster images. The result is a ticket that:

- **Resists screenshot cloning** — any lossy reproduction (screenshot, social media re-upload, photo-of-photo) destroys the embedded payload
- **Verifies fully offline** — no network dependency at the gate; ideal for venues with unreliable connectivity
- **Preserves privacy** — no personal data visible on the ticket surface
- **Provides tamper evidence** — every ticket is registered in a cryptographically linked blockchain
- **Authenticates the issuer** — private PoW blockchain ensures only the legitimate organiser can issue valid tickets

Built for the **Malawian events industry**, where smartphone penetration is rising (31.4% of adults in 2024) but network infrastructure at outdoor and peri-urban venues remains inconsistent.

---

## Architecture

EventChain follows a **four-layer architecture**:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: Supabase Backend                                  │
│  • PostgreSQL database (events, tickets, users)             │
│  • Supabase Storage (blockchain files, stego-ticket PNGs)   │
│  • Row Level Security (RLS) policies                        │
│  • Authentication & JWT session management                    │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Flutter Application (Dart)                        │
│  • UI, navigation, state management (Riverpod)              │
│  • Camera integration, local filesystem, device storage       │
│  • Orchestrates purchase & verification pipelines             │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Dart FFI Bridge (EventChainFFI)                   │
│  • JSON-serialised FFI interface to C++ shared library        │
│  • Async Dart wrappers: loadEvent, saveEvent, addTicket,    │
│    getEventSize, embedTicket, extractTicket                   │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: C++ Cryptographic Core (ISO C++17)                │
│  • Blockchain: Block structure, PoW mining, chain validation  │
│  • Steganography: 8×8 DCT, mid-frequency QIM embedding       │
│  • Cipher: Fibonacci XOR stream cipher (FNV-32 seeded)      │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Technologies

| Component | Technology | Version | Purpose |
|:---|:---|:---|:---|
| Mobile Framework | Flutter | 3.22 | Cross-platform UI, navigation, device integration |
| Language | Dart | 3.4 | Application logic, FFI bridge, state management |
| Cryptographic Core | C++ (ISO C++17) | — | Blockchain, DCT steganography, stream cipher |
| Native Interop | `dart:ffi` | Built-in | Direct C++ shared library invocation |
| State Management | Riverpod | 2.5 | Reactive, compile-time safe state management |
| Backend | Supabase | 2.0 | PostgreSQL, Storage, Auth, RLS |
| Image Codec | Flutter `image` / libpng | Built-in | Lossless PNG encoding for stego images |
| Blockchain Format | Custom `.web3chain` | v1 | Binary chain serialisation |

---

## Security Properties

| Threat | QR Code Ticketing | EventChain |
|:---|:---|:---|
| Screenshot cloning | Trivially exploitable | **Destroyed by QIM sensitivity** |
| Offline verification | Impossible | **Fully supported** |
| Server independence | None | **Complete local cryptographic proof** |
| Ticket privacy | Plaintext exposure | **Full data hidden in frequency domain** |
| Issuer authentication | None | **PoW blockchain with hash linkage** |
| Tamper detection | None | **Image + blockchain dual verification** |
| Ownership audit trail | None | **Private chain with full history** |

---

## Prerequisites

### Development Environment

- **Flutter SDK** 3.22 or higher
- **Dart SDK** 3.4 or higher
- **Android Studio** or **VS Code** with Flutter extension
- **NDK (Native Development Kit)** for C++ compilation
- **CMake** 3.10+ for native build
- **Git** for version control

### Target Device Requirements

- **Android API Level 23+** (Android 6.0 Marshmallow or higher)
- **Minimum 2 GB RAM**
- **ARMv8-A processor architecture** (recommended)
- **Camera** for gate verification
- **Storage** for blockchain files and ticket images

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/raytembo/event_chain.git
cd event_chain
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the Application

```bash
# For development on emulator or connected device
flutter run

# For release build
flutter build apk --release
```

---

## Core Workflows

### Ticket Purchase Pipeline (Customer)

```
Browse Events → Select Ticket Type → Payment (external) →
Blockchain Sync → Ticket Model Construction → PoW Mining →
DCT-QIM Embedding → Cloud Upload → Database Insertion →
Wallet Display
```

### Offline Gate Verification Pipeline (Gate Operator)

```
Camera Capture → DCT Extraction → Fibonacci Decryption →
Ticket Deserialisation → Blockchain Hash Validation →
Pass/Fail Result Display
```

---

## Testing

EventChain implements a **48-test automated suite** following the Flutter testing pyramid:

| Layer | Tests | Files | Duration | Environment |
|:---|:---|:---|:---|:---|
| **Unit Tests** | 39 | 5 | < 2s | Dart VM (`flutter test`) |
| **Widget Tests** | 8 | 2 | < 5s | Flutter test harness |
| **Integration Tests** | 1 | 1 | < 10s | Android emulator / device |
| **Total** | **48** | **8** | **< 17s** | — |

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# Run integration tests
flutter test integration_test/event_integration_test.dart
```

### Key Test Coverage

- **Data model serialisation/deserialisation** — JSON round-trips, type coercion, edge cases
- **State management** — Immutable `AuthState` transitions via `copyWith`
- **FFI bridge helpers** — Image format validation, constant mapping
- **Authentication UI** — Form validation, error presentation, routing logic
- **Native library loading** — `dlopen` validation, self-diagnostic execution

---

## Performance Benchmarks

Measured on reference hardware: **2 GB RAM, ARMv8-A, Android API 28**

| Operation | Requirement | Achieved |
|:---|:---|:---|
| Steganographic embedding | ≤ 5 seconds | **< 5s** |
| Offline verification | ≤ 3 seconds | **< 3s** |
| Chain depth scalability | No degradation at 10,000 blocks | **Verified** |
| Screenshot resistance | 100% extraction failure | **Verified** |
| Offline operation | Full capability without network | **Verified** |

---

## Known Issues & Limitations

1. **Embedding capacity constraints** — Low-resolution or low-texture poster images may fail embedding. Minimum recommended: 1080px width with varied detail.
2. **Private blockchain centralisation** — Single-organiser chain; integrity depends on organiser device security. No distributed consensus.
3. **Stream cipher cryptanalysis** — Fibonacci XOR selected for performance; formal security analysis against AES-256 recommended for future work.
4. **Android-only** — iOS support planned; requires C++ library compilation for `arm64` iOS targets and FFI bridge testing.
5. **Payment integration** — Airtel Money / TNM Mpamba integration excluded from current scope; requires external payment gateway APIs.

See [Chapter 5 of the dissertation](docs/dissertation/) for detailed limitation analysis and future work recommendations.

---

## Troubleshooting

### Build Issues

| Problem | Solution |
|:---|:---|
| `CMake Error: NDK not found` | Set `ANDROID_NDK` environment variable or specify path in `local.properties` |
| `Failed to load dynamic library` | Ensure `libeventchain.so` is in correct `jniLibs/<abi>/` directory for target architecture |
| `FFI ArgumentError on emulator` | x86 emulators not supported; use ARM emulator or physical device |
| `Supabase connection refused` | Verify URL and anon key in config; check RLS policies are not blocking anonymous access during development |

### Runtime Issues

| Problem | Solution |
|:---|:---|
| Screenshot rejection at gate | Ensure ticket is shown from EventChain wallet, not gallery or messaging app |
| "TAMPER DETECTED" universally | Redistribute fresh blockchain file; check file integrity during transfer |
| Embedding failure | Use higher-quality poster image (1080px+, varied texture, avoid flat colours) |
| Slow verification | Close background apps; ensure ≥ 500 MB free storage; restart app |

---

## Documentation

| Document | Location | Description |
|:---|:---|:---|
| **Dissertation (Chapters 1–5)** | `docs/dissertation/` | Full academic documentation of system design, implementation, and testing |
| **User Manual (Appendix A)** | `docs/user_manual/` | End-user guide for Organisers, Customers, and Gate Operators |
| **C++ Core Documentation** | `native/docs/` | Doxygen-generated docs for cryptographic modules |

---

## Contributing

This project was developed as a final year BSc ICT dissertation at the Malawi School of Government. While it is currently a research prototype, contributions are welcome for:

- iOS platform support
- Mobile money payment gateway integration
- Adaptive DCT coefficient selection algorithms
- Federated blockchain architecture extensions
- Automated performance regression testing

Please open an issue for discussion before submitting pull requests.

---

## Citation

If you use EventChain in academic work, please cite:

```bibtex
@misc{tembo2026eventchain,
  author = {Tembo, Raymond},
  title = {EventChain: A Blockchain-Steganographic Event Ticketing System},
  institution = {Malawi School of Government, Faculty of Information Technology},
  year = {2026},
  note = {BSc Information and Communication Technology Final Year Project}
}
```

---

## Acknowledgements

- **Supervisor:** Lughano Kayisi, Malawi School of Government
- **Institution:** Malawi School of Government, Faculty of Information Technology
- **Framework:** Flutter by Google, Supabase, Riverpod by Remi Rousselet
- **Cryptographic Foundations:** Ahmed, Natarajan & Rao (1974) on DCT; Chen & Wornell (2001) on QIM; Nakamoto (2008) on blockchain architecture

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

> **Academic Use Notice:** This software is provided as-is for educational and research purposes. Production deployment requires additional security auditing, formal cryptanalysis, and field trial validation as identified in the dissertation limitations section.

---

**Author:** Raymond Tembo (BICT/LL/G/C9/21)   
**Institution:** Malawi School of Government, Faculty of Information Technology  
**Date:** June 2026

---
