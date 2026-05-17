// lib/core/utils/image_converter.dart
//
// Thin utility — no external image-processing packages.
//
// The C++ steganography layer (stb_image_write + CImg) is the only encoder
// in this pipeline. It natively writes PNG and BMP. Any format request is
// fulfilled by asking the FFI layer to re-embed to the desired path extension
// rather than doing pixel-level conversion in Dart.
//
// Supported stego-safe output formats: PNG, BMP
// Lossy formats (JPEG, WebP) are NOT supported — they corrupt the payload.

import 'dart:io';

class ImageConverter {
  ImageConverter._();
  static final ImageConverter instance = ImageConverter._();

  /// Returns the file extension string for a given [ImageFormat] constant.
  static String extensionFor(int format) {
    switch (format) {
      case ImageFormat.bmp: return 'bmp';
      case ImageFormat.png:
      default:              return 'png';
    }
  }

  /// Returns true if [path]'s extension is a safe stego container.
  static bool isStegoSafe(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ext == 'png' || ext == 'bmp';
  }

  /// Copy [inputPath] to [outputPath] when both are the same format,
  /// or throw [UnsupportedError] if cross-format conversion is requested
  /// (use FFI re-embed for that instead).
  Future<void> copyIfSameFormat({
    required String inputPath,
    required String outputPath,
  }) async {
    final inExt  = inputPath.toLowerCase().split('.').last;
    final outExt = outputPath.toLowerCase().split('.').last;

    if (inExt != outExt) {
      throw UnsupportedError(
        'ImageConverter: cross-format copy ($inExt → $outExt) is not '
            'supported without an image-processing package. '
            'Use EventChainFFI.embedTicket() with the desired output extension instead.',
      );
    }

    await File(inputPath).copy(outputPath);
  }
}

// ── Image Format Constants ────────────────────────────────────────────────────
// Only PNG and BMP are valid stego containers in this pipeline.
// The C++ layer hard-rejects any other extension.
class ImageFormat {
  static const int png = 0;
  static const int bmp = 1;

  /// Returns true if [format] can be passed to embedTicket() as a stego output.
  static bool isStegoSafe(int format) => format == png || format == bmp;
}