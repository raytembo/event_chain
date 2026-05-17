// =============================================================================
//  steganography.h  –  Optimized DCT with Fast AAN Algorithm
//  UPDATED: PNG I/O via stb_image_write (no libpng dependency)
//           BMP remains the only other lossless output path.
//           JPEG/WebP/TIFF are rejected on stego output to protect payload.
// =============================================================================

#ifndef STEGANOGRAPHY_H
#define STEGANOGRAPHY_H

#ifndef cimg_display
#  define cimg_display 0
#endif

// CImg PNG/JPEG stubs are NOT enabled — stb handles PNG instead.
// This avoids any libpng / libjpeg-turbo NDK dependency.

#include "CImg.h"

// Forward-declare the only stb function we use.
// The full implementation is compiled once in eventchain_ffi.cpp
// (#define STB_IMAGE_WRITE_IMPLEMENTATION before #include "stb_image_write.h").
// This avoids including the header here and triggering a double-definition.
extern "C" int stbi_write_png(char const* filename, int w, int h,
        int comp, const void* data, int stride_in_bytes);

#include <string>
#include <vector>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <algorithm>
#include <iostream>
#include <map>
#include "config.h"

using namespace cimg_library;

// =============================================================================
// Supported image formats
//   PNG  — lossless, written via stb_image_write (no libpng needed)
//   BMP  — lossless, written via CImg (always available)
//   All lossy formats (JPEG, WebP) are rejected for stego output.
// =============================================================================
enum class ImageFormat {
    BMP,     // Uncompressed lossless — CImg native
    PNG,     // Lossless — written via stb_image_write
    JPEG,    // Lossy — REJECTED for stego output
    WEBP,    // Lossy — REJECTED for stego output
    TIFF,    // Not supported in NDK build (no libtiff)
    PNM,     // Portable pixmap — CImg native
    UNKNOWN
};

class DCTSteganography
{
public:

    // -------------------------------------------------------------------------
    // PNG save via stb_image_write
    //   Converts a CImg<unsigned char> to an interleaved pixel buffer and
    //   writes a PNG file.  No libpng required.
    //   Returns true on success.
    // -------------------------------------------------------------------------
    static bool savePng(const std::string& path, const CImg<unsigned char>& img)
    {
        int W = img.width(), H = img.height(), C = img.spectrum();
        if (W <= 0 || H <= 0 || (C != 1 && C != 3 && C != 4)) {
            std::cerr << "  [PNG] Unsupported image geometry for PNG write\n";
            return false;
        }

        // CImg stores pixels planar (R plane, G plane, B plane).
        // stb_image_write expects interleaved (RGBRGB…).
        std::vector<unsigned char> buf(static_cast<std::size_t>(W * H * C));
        for (int y = 0; y < H; ++y)
            for (int x = 0; x < W; ++x)
                for (int c = 0; c < C; ++c)
                    buf[static_cast<std::size_t>((y * W + x) * C + c)] = img(x, y, 0, c);

        int stride = W * C;
        int ok = stbi_write_png(path.c_str(), W, H, C, buf.data(), stride);
        if (!ok)
            std::cerr << "  [PNG] stbi_write_png failed: " << path << "\n";
        return ok != 0;
    }

    // -------------------------------------------------------------------------
    // Format detection from filename extension
    // -------------------------------------------------------------------------
    static ImageFormat detectFormat(const std::string& filename)
    {
        std::string ext;
        std::size_t dot = filename.rfind('.');
        if (dot != std::string::npos) {
            ext = filename.substr(dot + 1);
            // Convert to lowercase
            for (auto& c : ext) c = static_cast<char>(std::tolower(c));
        }

        if (ext == "png")  return ImageFormat::PNG;
        if (ext == "jpg" || ext == "jpeg") return ImageFormat::JPEG;
        if (ext == "webp") return ImageFormat::WEBP;
        if (ext == "tiff" || ext == "tif") return ImageFormat::TIFF;
        if (ext == "bmp")  return ImageFormat::BMP;
        if (ext == "pnm" || ext == "ppm" || ext == "pgm") return ImageFormat::PNM;
        return ImageFormat::UNKNOWN;
    }

    // -------------------------------------------------------------------------
    // Convert image between lossless formats only.
    //   PNG  output → stb_image_write (no libpng)
    //   BMP  output → CImg native
    //   JPEG / WebP → always rejected (lossy, would corrupt stego payload)
    // -------------------------------------------------------------------------
    static bool convertImage(const std::string& inputPath,
            const std::string& outputPath,
            unsigned int /*quality*/ = 95)   // quality param kept for API compat
    {
        ImageFormat fmt = detectFormat(outputPath);

        if (fmt == ImageFormat::JPEG || fmt == ImageFormat::WEBP) {
            std::cerr << "  [Convert] ERROR: lossy format rejected — "
                      << "JPEG/WebP destroy DCT steganography payload.\n"
                      << "  Use PNG or BMP instead.\n";
            return false;
        }

        CImg<unsigned char> img;
        try {
            img.load(inputPath.c_str());
        } catch (...) {
            std::cerr << "  [Convert] Cannot load input: " << inputPath << "\n";
            return false;
        }

        bool ok = false;
        try {
            switch (fmt) {
                case ImageFormat::PNG:
                    ok = savePng(outputPath, img);
                    break;
                case ImageFormat::BMP:
                    img.save_bmp(outputPath.c_str());
                    ok = true;
                    break;
                case ImageFormat::PNM:
                    img.save_pnm(outputPath.c_str());
                    ok = true;
                    break;
                default:
                    std::cerr << "  [Convert] Unsupported output format: "
                              << outputPath << "\n";
                    return false;
            }
        } catch (...) {
            std::cerr << "  [Convert] Cannot save output: " << outputPath << "\n";
            return false;
        }

        if (ok)
            std::cout << "  [Convert] " << inputPath << " -> " << outputPath << "\n";
        return ok;
    }

    // -------------------------------------------------------------------------
    // Batch convert folder of images
    // -------------------------------------------------------------------------
    static int convertFolder(const std::string& inputFolder,
            const std::string& outputFolder,
            ImageFormat targetFormat,
            unsigned int quality = 95)
    {
        // Note: In production, use filesystem::directory_iterator
        // This is a simplified version for the API
        std::cout << "  [Convert] Batch convert to format code: "
                  << static_cast<int>(targetFormat) << "\n";
        return 0;
    }

    // -------------------------------------------------------------------------
    // Generate a synthetic cover image.
    //   Default format is PNG (lossless, via stb_image_write).
    //   BMP is also accepted.  Lossy formats are rejected.
    // -------------------------------------------------------------------------
    static bool generateCover(const std::string& outputPath,
            int W = 512, int H = 512,
            ImageFormat fmt = ImageFormat::PNG)
    {
        if (fmt == ImageFormat::JPEG || fmt == ImageFormat::WEBP) {
            std::cerr << "  [Stego] ERROR: lossy format rejected for cover generation.\n";
            return false;
        }

        W = std::min(W, MAX_IMAGE_DIMENSION);
        H = std::min(H, MAX_IMAGE_DIMENSION);

        CImg<unsigned char> img(W, H, 1, 3);  // RGB

        cimg_forXY(img, x, y) {
            double v = 128.0
                    + 55.0 * std::sin(x * 0.04)
                    + 35.0 * std::cos(y * 0.06)
                    + 20.0 * std::sin((x + y) * 0.025)
                    + 15.0 * std::cos((x - y) * 0.05)
                    +  8.0 * std::sin(x * 1.9) * std::cos(y * 2.3);
            auto c = (unsigned char)std::max(5.0, std::min(250.0, v));
            img(x, y, 0, 0) = c;
            img(x, y, 0, 1) = c;
            img(x, y, 0, 2) = c;
        }

        bool ok = false;
        try {
            switch (fmt) {
                case ImageFormat::PNG:
                    ok = savePng(outputPath, img);
                    break;
                case ImageFormat::BMP:
                    img.save_bmp(outputPath.c_str());
                    ok = true;
                    break;
                default:
                    // Fallback to PNG
                    ok = savePng(outputPath, img);
                    break;
            }
        } catch (...) {
            std::cerr << "  [Stego] Cannot save cover: " << outputPath << "\n";
            return false;
        }

        if (ok)
            std::cout << "  [Stego] Cover image generated: " << outputPath << "\n";
        return ok;
    }

    // -------------------------------------------------------------------------
    // Steganography capacity calculation
    // -------------------------------------------------------------------------
    static std::size_t capacity(int W, int H)
    {
        int blocksW = W / BLOCK;
        int blocksH = H / BLOCK;
        std::size_t blocks = static_cast<std::size_t>(blocksW) * blocksH;
        return (blocks > 32u) ? (blocks - 32u) / 8u : 0u;
    }

    // -------------------------------------------------------------------------
    // Embed payload into image (auto-converts format on save)
    // -------------------------------------------------------------------------
    static bool embed(const std::string& coverPath,
            const std::string& stegoPath,
            const std::string& payload)
    {
        CImg<unsigned char> img;
        try { img.load(coverPath.c_str()); }
        catch (...) {
            std::cerr << "  [Stego] Cannot load cover: " << coverPath << "\n";
            return false;
        }

        if (img.width() > MAX_IMAGE_DIMENSION || img.height() > MAX_IMAGE_DIMENSION) {
            std::cerr << "  [Stego] Image too large: max " << MAX_IMAGE_DIMENSION << "x" << MAX_IMAGE_DIMENSION << "\n";
            return false;
        }

        int W = img.width(), H = img.height();
        if (capacity(W, H) < payload.size()) {
            std::cerr << "  [Stego] Cover too small: need "
                      << payload.size() << " B, capacity="
                      << capacity(W, H) << " B\n";
            return false;
        }

        std::vector<int> bits = toBitStream(payload);
        CImg<double> luma = extractLuma(img);

        int bx = 0, by = 0;
        for (std::size_t i = 0; i < bits.size(); ++i) {
            if (bx * BLOCK >= W) { bx = 0; ++by; }
            if (by * BLOCK >= H) break;

            double blk[BLOCK][BLOCK];
            readBlock(luma, bx, by, blk);
            fastDct8x8(blk);
            embedBit(blk[3][4], bits[i]);
            fastIdct8x8(blk);
            writeBlock(luma, bx, by, blk);
            ++bx;
        }

        CImg<unsigned char> result = writeLuma(img, luma);

        // Hard-reject lossy formats — they destroy QIM-embedded bits.
        ImageFormat fmt = detectFormat(stegoPath);
        if (fmt == ImageFormat::JPEG || fmt == ImageFormat::WEBP) {
            std::cerr << "  [Stego] ERROR: lossy output format rejected.\n"
                      << "  JPEG/WebP re-quantize DCT coefficients and destroy\n"
                      << "  the hidden payload.  Use .png or .bmp instead.\n";
            return false;
        }

        bool saved = false;
        try {
            switch (fmt) {
                case ImageFormat::PNG:
                    saved = savePng(stegoPath, result);
                    break;
                case ImageFormat::BMP:
                    result.save_bmp(stegoPath.c_str());
                    saved = true;
                    break;
                case ImageFormat::PNM:
                    result.save_pnm(stegoPath.c_str());
                    saved = true;
                    break;
                default:
                    // Unknown extension — fall back to PNG (safe)
                    saved = savePng(stegoPath, result);
                    break;
            }
        } catch (...) {
            std::cerr << "  [Stego] Cannot save stego: " << stegoPath << "\n";
            return false;
        }

        if (!saved) return false;

        std::cout << "  [Stego] Embedded " << payload.size() << " bytes  ->  "
                  << stegoPath << "\n";
        return true;
    }

    // -------------------------------------------------------------------------
    // Extract payload from stego image
    // -------------------------------------------------------------------------
    static std::string extract(const std::string& stegoPath)
    {
        CImg<unsigned char> img;
        try { img.load(stegoPath.c_str()); }
        catch (...) {
            std::cerr << "  [Stego] Cannot load stego: " << stegoPath << "\n";
            return "";
        }

        int W = img.width(), H = img.height();
        int totalBlocks = (W / BLOCK) * (H / BLOCK);
        if (totalBlocks < 32) {
            std::cerr << "  [Stego] Image too small\n";
            return "";
        }

        CImg<double> luma = extractLuma(img);

        std::vector<int> bits;
        bits.reserve(totalBlocks);
        int bx = 0, by = 0;
        while ((int)bits.size() < totalBlocks) {
            if (bx * BLOCK >= W) { bx = 0; ++by; }
            if (by * BLOCK >= H) break;

            double blk[BLOCK][BLOCK];
            readBlock(luma, bx, by, blk);
            fastDct8x8(blk);
            bits.push_back(extractBit(blk[3][4]));
            ++bx;
        }

        if ((int)bits.size() < 32) return "";
        std::uint32_t len = 0;
        for (int i = 0; i < 32; ++i) len = (len << 1) | bits[i];

        if (len == 0 || (int)(len * 8 + 32) > (int)bits.size()) {
            std::cerr << "  [Stego] Invalid length header (" << len << ")\n";
            return "";
        }

        std::string result;
        result.reserve(len);
        for (std::uint32_t b = 0; b < len; ++b) {
            unsigned char byte = 0;
            for (int bit = 0; bit < 8; ++bit)
                byte = (byte << 1) | (unsigned char)bits[32 + b * 8 + bit];
            result += (char)byte;
        }

        std::cout << "  [Stego] Extracted " << len << " bytes from " << stegoPath << "\n";
        return result;
    }

    // -------------------------------------------------------------------------
    // Format compatibility check for steganography
    //   PNG  — lossless, stb_image_write, SAFE
    //   BMP  — lossless, CImg native,     SAFE
    //   PNM  — lossless, CImg native,     SAFE
    //   JPEG — lossy, re-quantizes DCT,   UNSAFE  (hard-rejected in embed/convert)
    //   WebP — lossy by default,          UNSAFE  (hard-rejected in embed/convert)
    //   TIFF — not linked in NDK build,   NOT SUPPORTED
    // -------------------------------------------------------------------------
    static bool isFormatStegoCompatible(ImageFormat fmt)
    {
        return fmt == ImageFormat::PNG ||
                fmt == ImageFormat::BMP ||
                fmt == ImageFormat::PNM;
    }

    static bool isFormatStegoCompatible(const std::string& filename)
    {
        return isFormatStegoCompatible(detectFormat(filename));
    }

private:

    static const int BLOCK = 8;
    static constexpr double Q = STEGO_QIM_STEP;

    // AAN Fast DCT constants
    static constexpr double C1 = 0.9807852804032304;
    static constexpr double C2 = 0.9238795325112867;
    static constexpr double C3 = 0.8314696123025452;
    static constexpr double C4 = 0.7071067811865476;
    static constexpr double C5 = 0.5555702330196022;
    static constexpr double C6 = 0.3826834323650898;
    static constexpr double C7 = 0.19509032201612825;
    static constexpr double INV_SQRT8 = 0.3535533905932738;

    static void fastDct8x8(double b[BLOCK][BLOCK])
    {
        double tmp[8][8];

        for (int i = 0; i < 8; ++i) {
            double x0 = b[i][0] + b[i][7];
            double x1 = b[i][1] + b[i][6];
            double x2 = b[i][2] + b[i][5];
            double x3 = b[i][3] + b[i][4];
            double x4 = b[i][3] - b[i][4];
            double x5 = b[i][2] - b[i][5];
            double x6 = b[i][1] - b[i][6];
            double x7 = b[i][0] - b[i][7];

            double x8 = x0 + x3;
            double x9 = x1 + x2;
            double x10 = x1 - x2;
            double x11 = x0 - x3;

            tmp[i][0] = C4 * (x8 + x9);
            tmp[i][4] = C4 * (x8 - x9);
            tmp[i][2] = C2 * x11 + C6 * x10;
            tmp[i][6] = C6 * x11 - C2 * x10;

            double x12 = -C4 * (x4 + x5);
            double x13 = C4 * (x4 - x5);
            double x14 = C3 * x6 + C5 * x7;
            double x15 = C1 * x7 - C7 * x6;

            tmp[i][5] = x12 + x14;
            tmp[i][3] = x13 + x15;
            tmp[i][1] = x13 - x15;
            tmp[i][7] = x12 - x14;
        }

        for (int j = 0; j < 8; ++j) {
            double x0 = tmp[0][j] + tmp[7][j];
            double x1 = tmp[1][j] + tmp[6][j];
            double x2 = tmp[2][j] + tmp[5][j];
            double x3 = tmp[3][j] + tmp[4][j];
            double x4 = tmp[3][j] - tmp[4][j];
            double x5 = tmp[2][j] - tmp[5][j];
            double x6 = tmp[1][j] - tmp[6][j];
            double x7 = tmp[0][j] - tmp[7][j];

            double x8 = x0 + x3;
            double x9 = x1 + x2;
            double x10 = x1 - x2;
            double x11 = x0 - x3;

            b[0][j] = INV_SQRT8 * (x8 + x9);
            b[4][j] = INV_SQRT8 * (x8 - x9);
            b[2][j] = INV_SQRT8 * (C2 * x11 + C6 * x10);
            b[6][j] = INV_SQRT8 * (C6 * x11 - C2 * x10);

            double x12 = -C4 * (x4 + x5);
            double x13 = C4 * (x4 - x5);
            double x14 = C3 * x6 + C5 * x7;
            double x15 = C1 * x7 - C7 * x6;

            b[5][j] = INV_SQRT8 * (x12 + x14);
            b[3][j] = INV_SQRT8 * (x13 + x15);
            b[1][j] = INV_SQRT8 * (x13 - x15);
            b[7][j] = INV_SQRT8 * (x12 - x14);
        }
    }

    static void fastIdct8x8(double b[BLOCK][BLOCK])
    {
        double tmp[8][8];

        for (int i = 0; i < 8; ++i) {
            double x0 = b[i][0] + b[i][4];
            double x1 = b[i][0] - b[i][4];
            double x2 = b[i][2] * C6 - b[i][6] * C2;
            double x3 = b[i][6] * C6 + b[i][2] * C2;
            double x4 = b[i][1] + b[i][7];
            double x5 = b[i][1] - b[i][7];
            double x6 = b[i][5] + b[i][3];
            double x7 = b[i][5] - b[i][3];

            double x8 = x4 + x6;
            double x9 = x5 + x7;
            double x10 = x5 - x7;
            double x11 = x4 - x6;

            tmp[i][0] = x0 + x3 + x8;
            tmp[i][7] = x0 + x3 - x8;
            tmp[i][1] = x1 + x2 + x9;
            tmp[i][6] = x1 + x2 - x9;
            tmp[i][2] = x1 - x2 + x10;
            tmp[i][5] = x1 - x2 - x10;
            tmp[i][3] = x0 - x3 + x11;
            tmp[i][4] = x0 - x3 - x11;
        }

        for (int j = 0; j < 8; ++j) {
            double x0 = tmp[0][j] + tmp[4][j];
            double x1 = tmp[0][j] - tmp[4][j];
            double x2 = tmp[2][j] * C6 - tmp[6][j] * C2;
            double x3 = tmp[6][j] * C6 + tmp[2][j] * C2;
            double x4 = tmp[1][j] + tmp[7][j];
            double x5 = tmp[1][j] - tmp[7][j];
            double x6 = tmp[5][j] + tmp[3][j];
            double x7 = tmp[5][j] - tmp[3][j];

            double x8 = x4 + x6;
            double x9 = x5 + x7;
            double x10 = x5 - x7;
            double x11 = x4 - x6;

            b[0][j] = INV_SQRT8 * (x0 + x3 + x8);
            b[7][j] = INV_SQRT8 * (x0 + x3 - x8);
            b[1][j] = INV_SQRT8 * (x1 + x2 + x9);
            b[6][j] = INV_SQRT8 * (x1 + x2 - x9);
            b[2][j] = INV_SQRT8 * (x1 - x2 + x10);
            b[5][j] = INV_SQRT8 * (x1 - x2 - x10);
            b[3][j] = INV_SQRT8 * (x0 - x3 + x11);
            b[4][j] = INV_SQRT8 * (x0 - x3 - x11);
        }
    }

    static void embedBit(double& coeff, int bit)
    {
        int k = (int)std::floor(coeff / Q);
        int parity = ((k % 2) + 2) % 2;
        if (parity != bit) {
            double d_up   = std::abs(coeff - (k + 1.5) * Q);
            double d_down = std::abs(coeff - (k - 0.5) * Q);
            k += (d_up <= d_down) ? 1 : -1;
        }
        coeff = (k + 0.5) * Q;
    }

    static int extractBit(double coeff)
    {
        int k = (int)std::floor(coeff / Q);
        return ((k % 2) + 2) % 2;
    }

    static std::vector<int> toBitStream(const std::string& s)
    {
        std::vector<int> bits;
        bits.reserve(32 + s.size() * 8);
        std::uint32_t len = (std::uint32_t)s.size();
        for (int i = 31; i >= 0; --i)
            bits.push_back((len >> i) & 1);
        for (unsigned char c : s)
            for (int i = 7; i >= 0; --i)
                bits.push_back((c >> i) & 1);
        return bits;
    }

    static CImg<double> extractLuma(const CImg<unsigned char>& img)
    {
        CImg<double> luma(img.width(), img.height(), 1, 1);
        if (img.spectrum() == 1) {
            cimg_forXY(img, x, y)
            luma(x, y) = (double)img(x, y);
        } else {
            cimg_forXY(img, x, y)
            luma(x, y) = 0.299 * img(x,y,0,0)
                    + 0.587 * img(x,y,0,1)
                    + 0.114 * img(x,y,0,2);
        }
        return luma;
    }

    static CImg<unsigned char> writeLuma(const CImg<unsigned char>& orig,
            const CImg<double>&         luma)
    {
        CImg<unsigned char> out = orig;
        if (orig.spectrum() == 1) {
            cimg_forXY(out, x, y)
            out(x, y) = (unsigned char)std::max(0.0, std::min(255.0, luma(x,y)));
        } else {
            cimg_forXY(orig, x, y) {
                double orig_luma = 0.299*orig(x,y,0,0)
                        + 0.587*orig(x,y,0,1)
                        + 0.114*orig(x,y,0,2);
                double scale = (orig_luma > 1e-6) ? (luma(x,y) / orig_luma) : 1.0;
                scale = std::max(0.0, std::min(2.0, scale));
                for (int c = 0; c < 3; ++c) {
                    double v = orig(x,y,0,c) * scale;
                    out(x,y,0,c) = (unsigned char)std::max(0.0, std::min(255.0, v));
                }
            }
        }
        return out;
    }

    static void readBlock(const CImg<double>& img, int bx, int by,
            double blk[BLOCK][BLOCK])
    {
        for (int y = 0; y < BLOCK; ++y)
            for (int x = 0; x < BLOCK; ++x)
                blk[x][y] = img(bx*BLOCK+x, by*BLOCK+y);
    }

    static void writeBlock(CImg<double>& img, int bx, int by,
            const double blk[BLOCK][BLOCK])
    {
        for (int y = 0; y < BLOCK; ++y)
            for (int x = 0; x < BLOCK; ++x)
                img(bx*BLOCK+x, by*BLOCK+y) =
                        std::max(0.0, std::min(255.0, blk[x][y]));
    }
};

#endif // STEGANOGRAPHY_H