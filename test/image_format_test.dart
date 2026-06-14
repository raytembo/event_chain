// Unit tests for the ImageFormat helper in eventchain_ffi.dart.
//
// Pure Dart logic — no DynamicLibrary / native .so required.

import 'package:flutter_test/flutter_test.dart';
import 'package:eventchain/core/ffi_bridge/eventchain_ffi.dart';

void main() {
  group('ImageFormat', () {
    test('PNG is a valid stego container format', () {
      expect(ImageFormat.isStegoSafe(ImageFormat.png), isTrue);
    });

    test('BMP is a valid stego container format', () {
      expect(ImageFormat.isStegoSafe(ImageFormat.bmp), isTrue);
    });

    test('formats other than PNG/BMP are rejected', () {
      expect(ImageFormat.isStegoSafe(2), isFalse); // e.g. a would-be JPEG code
      expect(ImageFormat.isStegoSafe(-1), isFalse);
    });

    test('format constants map to the expected integer codes', () {
      expect(ImageFormat.png, 0);
      expect(ImageFormat.bmp, 1);
    });
  });
}
