// steganography.h  –  DIAGNOSTIC EDITION (FULLY CORRECTED)
// Drop-in replacement featuring exact separable 2D DCT/IDCT and robust pixel rounding.

#ifndef STEGANOGRAPHY_H
#define STEGANOGRAPHY_H

#ifndef cimg_display
#  define cimg_display 0
#endif

#include "CImg.h"
extern "C" {
    int           stbi_write_png(const char* filename, int w, int h,
                                 int comp, const void* data, int stride_bytes);
    unsigned char* stbi_load(const char* filename, int* x, int* y,
                             int* channels_in_file, int desired_channels);
    void           stbi_image_free(void* retval_from_stbi_load);
}

#include <string>
#include <vector>
#include <array>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <algorithm>
#include <iostream>
#include <sstream>
#include <iomanip>
#include <numeric>
#include <functional>
#include "../config.h"

using namespace cimg_library;

static constexpr int ZIGZAG[64][2] = {
        {0,0}, {0,1}, {1,0}, {2,0}, {1,1}, {0,2}, {0,3}, {1,2},
        {2,1}, {3,0}, {4,0}, {3,1}, {2,2}, {1,3}, {0,4}, {0,5},
        {1,4}, {2,3}, {3,2}, {4,1}, {5,0}, {6,0}, {5,1}, {4,2},
        {3,3}, {2,4}, {1,5}, {0,6}, {0,7}, {1,6}, {2,5}, {3,4},
        {4,3}, {5,2}, {6,1}, {7,0}, {7,1}, {6,2}, {5,3}, {4,4},
        {3,5}, {2,6}, {1,7}, {2,7}, {3,6}, {4,5}, {5,4}, {6,3},
        {7,2}, {7,3}, {6,4}, {5,5}, {4,6}, {3,7}, {4,7}, {5,6},
        {6,5}, {7,4}, {7,5}, {6,6}, {5,7}, {6,7}, {7,6}, {7,7}
};

static constexpr int ZIGZAG_MID_START = 5;
static constexpr int ZIGZAG_MID_END   = 27;
static constexpr int ZIGZAG_MID_COUNT = ZIGZAG_MID_END - ZIGZAG_MID_START + 1;
static constexpr int BITS_PER_BLOCK   = 5;
static constexpr double QIM_Q         = STEGO_QIM_STEP;

enum class ImageFormat { BMP, PNG, JPEG, WEBP, TIFF, PNM, UNKNOWN };

struct ExtractResult {
    bool        success = false;
    std::string payload;          
    std::string error;            
    std::size_t bitsRead = 0;
    std::uint32_t headerLen = 0;
    std::uint32_t headerChk = 0;
    std::uint32_t computedChk = 0;
    int         blocksUsed = 0;
    int         imageW = 0, imageH = 0;
};

class DCTSteganography
{
public:
    static bool generateCover(const std::string& outputPath,
            int W = 512, int H = 512,
            ImageFormat fmt = ImageFormat::PNG)
    {
        if (fmt == ImageFormat::JPEG || fmt == ImageFormat::WEBP) {
            std::cerr << "  [Stego] Lossy format rejected for cover generation.\n";
            return false;
        }
        W = std::min(W, MAX_IMAGE_DIMENSION);
        H = std::min(H, MAX_IMAGE_DIMENSION);

        CImg<unsigned char> img(W, H, 1, 3);
        cimg_forXY(img, x, y) {
            // Red Channel: Dominant smooth horizontal/diagonal waves
            double r_v = 128.0
                    + 55.0 * std::sin(x * 0.035)
                    + 35.0 * std::cos(y * 0.025)
                    + 25.0 * std::sin((x + y) * 0.015);

            // Green Channel: Phase-shifted vertical and cross waves
            double g_v = 128.0
                    + 55.0 * std::sin(y * 0.040 + 1.5)
                    + 35.0 * std::cos(x * 0.030)
                    + 25.0 * std::sin((x - y) * 0.020);

            // Blue Channel: High-frequency complex textures for depth
            double b_v = 128.0
                    + 55.0 * std::cos(x * 0.025 - 0.8)
                    + 35.0 * std::sin(y * 0.045 + 0.5)
                    + 20.0 * std::cos((x + y) * 0.035)
                    + 12.0 * std::sin(x * 1.5) * std::cos(y * 1.8);

            // Clamp and assign unique values to each channel to construct a full-color image
            img(x, y, 0, 0) = (unsigned char)std::max(5.0, std::min(250.0, r_v));
            img(x, y, 0, 1) = (unsigned char)std::max(5.0, std::min(250.0, g_v));
            img(x, y, 0, 2) = (unsigned char)std::max(5.0, std::min(250.0, b_v));
        }
        bool ok = saveImage(img, outputPath, fmt);
        if (ok) std::cout << "  [Stego] Colorful cover generated: " << outputPath << "\n";
        return ok;
    }

    static std::size_t capacity(int W, int H)
    {
        int blocksW = W / 8;
        int blocksH = H / 8;
        std::size_t totalBits = static_cast<std::size_t>(blocksW) * blocksH * BITS_PER_BLOCK;
        if (totalBits < 64u + 8u * BITS_PER_BLOCK) return 0;
        return (totalBits - 64u) / 8u;
    }

    static bool embed(const std::string& coverPath,
            const std::string& stegoPath,
            const std::string& payload,
            const std::string& key = "")
    {
        CImg<unsigned char> img;
        try { img = loadImageStb(coverPath); }
        catch (const std::exception& e) {
            std::cerr << "  [Stego-ERR] Cannot load cover: " << e.what() << "\n";
            return false;
        }

        if (img.width() > MAX_IMAGE_DIMENSION || img.height() > MAX_IMAGE_DIMENSION) {
            int newW, newH;
            if (img.width() >= img.height()) {
                newW = MAX_IMAGE_DIMENSION;
                newH = static_cast<int>(
                    static_cast<double>(img.height()) * MAX_IMAGE_DIMENSION / img.width());
            } else {
                newH = MAX_IMAGE_DIMENSION;
                newW = static_cast<int>(
                    static_cast<double>(img.width()) * MAX_IMAGE_DIMENSION / img.height());
            }
            newW = (newW / 8) * 8;
            newH = (newH / 8) * 8;
            if (newW < 8 || newH < 8) {
                std::cerr << "  [Stego-ERR] Cover too small after rescale.\n";
                return false;
            }
            img.resize(newW, newH, 1, img.spectrum(), 3);
            std::cout << "  [Stego] Cover rescaled to " << newW << "x" << newH << "\n";
        }

        const int W = img.width(), H = img.height();
        const std::size_t cap = capacity(W, H);
        if (payload.size() > cap) {
            std::cerr << "  [Stego-ERR] Payload too large: " << payload.size()
                      << " B vs capacity " << cap << " B\n";
            return false;
        }

        const std::uint32_t chk = checksum32(payload);
        std::vector<int> bits = buildBitstream(payload, chk);

        CImg<double> luma = extractLuma(img);
        KeyedCoeffSelector sel(key);

        int bx = 0, by = 0;
        std::size_t bitIdx = 0;
        const int numBlocksX = W / 8, numBlocksY = H / 8;

        while (bitIdx < bits.size()) {
            if (bx >= numBlocksX) { bx = 0; ++by; }
            if (by >= numBlocksY) break;

            double blk[8][8];
            readBlock(luma, bx, by, blk);
            fastDct8x8(blk);

            auto coeffPositions = sel.positions(bx * numBlocksY + by);
            for (int slot = 0; slot < BITS_PER_BLOCK && bitIdx < bits.size(); ++slot) {
                int r = ZIGZAG[coeffPositions[slot]][0];
                int c = ZIGZAG[coeffPositions[slot]][1];
                embedBit(blk[r][c], bits[bitIdx++]);
            }

            fastIdct8x8(blk);
            writeBlock(luma, bx, by, blk);
            ++bx;
        }

        CImg<unsigned char> result = writeLuma(img, luma);
        const ImageFormat fmt = detectFormat(stegoPath);
        if (fmt == ImageFormat::JPEG || fmt == ImageFormat::WEBP) {
            std::cerr << "  [Stego-ERR] Lossy output rejected.\n";
            return false;
        }

        const bool saved = saveImage(result, stegoPath, fmt);
        if (saved) {
            std::cout << "  [Stego] Embedded " << payload.size()
                      << " B (chk=" << chk << ") -> " << stegoPath << "\n";
        }
        return saved;
    }

    static std::string extract(const std::string& stegoPath,
            const std::string& key = "")
    {
        auto r = diagnosticExtract(stegoPath, key);
        return r.success ? r.payload : "";
    }

    static ExtractResult diagnosticExtract(const std::string& stegoPath,
            const std::string& key = "")
    {
        ExtractResult res;
        CImg<unsigned char> img;
        try {
            img = loadImageStb(stegoPath);
        } catch (const std::exception& e) {
            res.error = std::string("loadImageStb failed: ") + e.what();
            std::cerr << "  [Stego-ERR] " << res.error << "\n";
            return res;
        }

        res.imageW = img.width();
        res.imageH = img.height();
        const int W = img.width(), H = img.height();
        const int numBlocksX = W / 8, numBlocksY = H / 8;
        const int totalBlocks = numBlocksX * numBlocksY;
        if (totalBlocks < 16) {
            res.error = "Image too small for DCT (< 16 blocks)";
            std::cerr << "  [Stego-ERR] " << res.error << "\n";
            return res;
        }

        CImg<double> luma = extractLuma(img);
        KeyedCoeffSelector sel(key);
        std::vector<int> bits;
        bits.reserve(static_cast<std::size_t>(totalBlocks) * BITS_PER_BLOCK);

        int bx = 0, by = 0;
        for (int b = 0; b < totalBlocks; ++b) {
            if (bx >= numBlocksX) { bx = 0; ++by; }
            if (by >= numBlocksY) break;

            double blk[8][8];
            readBlock(luma, bx, by, blk);
            fastDct8x8(blk);

            auto coeffPositions = sel.positions(bx * numBlocksY + by);
            for (int slot = 0; slot < BITS_PER_BLOCK; ++slot) {
                int r = ZIGZAG[coeffPositions[slot]][0];
                int c = ZIGZAG[coeffPositions[slot]][1];
                bits.push_back(extractBit(blk[r][c]));
            }
            ++bx;
        }
        res.bitsRead = bits.size();
        res.blocksUsed = totalBlocks;

        if (static_cast<int>(bits.size()) < 64) {
            res.error = "Not enough bits for header (need 64, got " +
                        std::to_string(bits.size()) + ")";
            std::cerr << "  [Stego-ERR] " << res.error << "\n";
            return res;
        }

        std::uint32_t len = 0;
        for (int i = 0; i < 32; ++i) len = (len << 1) | bits[i];
        std::uint32_t storedChk = 0;
        for (int i = 0; i < 32; ++i) storedChk = (storedChk << 1) | bits[32 + i];

        res.headerLen = len;
        res.headerChk = storedChk;

        if (len == 0 || len > (bits.size() - 64) / 8) {
            res.error = "Invalid length header: " + std::to_string(len) +
                        " (max valid: " + std::to_string((bits.size()-64)/8) + ")";
            std::cerr << "  [Stego-ERR] " << res.error << "\n";
            return res;
        }

        std::string payload;
        payload.reserve(len);
        for (std::uint32_t b = 0; b < len; ++b) {
            unsigned char byte = 0;
            for (int bit = 0; bit < 8; ++bit)
                byte = (byte << 1) | static_cast<unsigned char>(bits[64 + b * 8 + bit]);
            payload += static_cast<char>(byte);
        }

        res.computedChk = checksum32(payload);
        if (res.computedChk != storedChk) {
            res.error = "Checksum mismatch: stored=" + std::to_string(storedChk) +
                        " computed=" + std::to_string(res.computedChk);
            std::cerr << "  [Stego-ERR] " << res.error << "\n";
            return res;
        }

        res.success = true;
        res.payload = payload;
        std::cout << "  [Stego] Extracted " << len << " B, checksum OK\n";
        return res;
    }

    static std::string selfTestRoundtrip(const std::string& coverPath,
                                          const std::string& stegoPath,
                                          const std::string& payload,
                                          const std::string& key = "")
    {
        std::ostringstream report;
        report << "=== DCT Stego Self-Test ===\n";

        bool emb = embed(coverPath, stegoPath, payload, key);
        report << "Embed: " << (emb ? "OK" : "FAIL") << "\n";
        if (!emb) return report.str();

        auto ex = diagnosticExtract(stegoPath, key);
        report << "Extract: " << (ex.success ? "OK" : "FAIL") << "\n";
        if (!ex.success) {
            report << "  Error: " << ex.error << "\n";
            report << "  Image: " << ex.imageW << "x" << ex.imageH << "\n";
            report << "  Bits:  " << ex.bitsRead << " (blocks=" << ex.blocksUsed << ")\n";
            report << "  Header len=" << ex.headerLen << " chk=" << ex.headerChk << "\n";
            return report.str();
        }

        report << "  Payload match: " << (ex.payload == payload ? "YES" : "NO") << "\n";
        report << "  Bytes: expected=" << payload.size() << " got=" << ex.payload.size() << "\n";
        if (ex.payload != payload) {
            report << "  Expected: " << hexDump(payload) << "\n";
            report << "  Got:      " << hexDump(ex.payload) << "\n";
        }
        return report.str();
    }

    static ImageFormat detectFormat(const std::string& filename)
    {
        std::string ext;
        const std::size_t dot = filename.rfind('.');
        if (dot != std::string::npos) {
            ext = filename.substr(dot + 1);
            for (auto& ch : ext) ch = static_cast<char>(std::tolower(ch));
        }
        if (ext == "png")                      return ImageFormat::PNG;
        if (ext == "bmp")                      return ImageFormat::BMP;
        if (ext == "jpg" || ext == "jpeg")     return ImageFormat::JPEG;
        if (ext == "webp")                     return ImageFormat::WEBP;
        if (ext == "tiff" || ext == "tif")     return ImageFormat::TIFF;
        if (ext == "pnm" || ext == "ppm" || ext == "pgm") return ImageFormat::PNM;
        return ImageFormat::UNKNOWN;
    }

    static bool isFormatStegoCompatible(const std::string& filename)
    {
        const auto fmt = detectFormat(filename);
        return fmt == ImageFormat::PNG || fmt == ImageFormat::BMP || fmt == ImageFormat::PNM;
    }

private:
    class KeyedCoeffSelector {
    public:
        explicit KeyedCoeffSelector(const std::string& key)
        {
            keyHash_ = 2166136261u;
            for (unsigned char c : key)
                keyHash_ = (keyHash_ ^ c) * 16777619u;
        }
        std::array<int, BITS_PER_BLOCK> positions(int blockIndex) const
        {
            std::array<int, ZIGZAG_MID_COUNT> pool;
            for (int i = 0; i < ZIGZAG_MID_COUNT; ++i)
                pool[i] = ZIGZAG_MID_START + i;

            uint32_t state = keyHash_ ^ static_cast<uint32_t>(blockIndex);
            for (int i = 0; i < BITS_PER_BLOCK; ++i) {
                state = lcg(state);
                int j = i + static_cast<int>(
                    state % static_cast<uint32_t>(ZIGZAG_MID_COUNT - i));
                std::swap(pool[i], pool[j]);
            }
            std::array<int, BITS_PER_BLOCK> result;
            for (int i = 0; i < BITS_PER_BLOCK; ++i)
                result[i] = pool[i];
            return result;
        }
    private:
        uint32_t keyHash_;
        static uint32_t lcg(uint32_t s) { return s * 1664525u + 1013904223u; }
    };

    static std::uint32_t checksum32(const std::string& data)
    {
        std::uint32_t a = 1, b = 0;
        for (unsigned char c : data) {
            a = (a + c) % 65521u;
            b = (b + a) % 65521u;
        }
        return (b << 16) | a;
    }

    static std::vector<int> buildBitstream(const std::string& s, std::uint32_t chk)
    {
        std::vector<int> bits;
        bits.reserve(64u + s.size() * 8u);
        const auto len = static_cast<std::uint32_t>(s.size());
        for (int i = 31; i >= 0; --i) bits.push_back((len >> i) & 1);
        for (int i = 31; i >= 0; --i) bits.push_back((chk >> i) & 1);
        for (unsigned char c : s)
            for (int i = 7; i >= 0; --i)
                bits.push_back((c >> i) & 1);
        return bits;
    }

    static void embedBit(double& coeff, int bit)
    {
        int k = static_cast<int>(std::floor(coeff / QIM_Q));
        const int parity = ((k % 2) + 2) % 2;
        if (parity != bit) {
            const double dUp   = std::abs(coeff - (k + 1.5) * QIM_Q);
            const double dDown = std::abs(coeff - (k - 0.5) * QIM_Q);
            k += (dUp <= dDown) ? 1 : -1;
        }
        coeff = (k + 0.5) * QIM_Q;
    }

    static int extractBit(double coeff)
    {
        const int k = static_cast<int>(std::floor(coeff / QIM_Q));
        return ((k % 2) + 2) % 2;
    }

    // UPDATED: High-precision Separable 2D Orthogonal Discrete Cosine Transform (DCT-II)
    static void fastDct8x8(double b[8][8])
    {
        double tmp[8][8];
        static const double pi = std::acos(-1.0);
        
        // Transform Rows sequentially
        for (int y = 0; y < 8; ++y) {
            for (int u = 0; u < 8; ++u) {
                double sum = 0.0;
                for (int x = 0; x < 8; ++x) {
                    sum += b[x][y] * std::cos((2 * x + 1) * u * pi / 16.0);
                }
                double cu = (u == 0) ? 1.0 / std::sqrt(2.0) : 1.0;
                tmp[u][y] = sum * cu * 0.5;
            }
        }
        // Transform Columns sequentially
        for (int u = 0; u < 8; ++u) {
            for (int v = 0; v < 8; ++v) {
                double sum = 0.0;
                for (int y = 0; y < 8; ++y) {
                    sum += tmp[u][y] * std::cos((2 * y + 1) * v * pi / 16.0);
                }
                double cv = (v == 0) ? 1.0 / std::sqrt(2.0) : 1.0;
                b[u][v] = sum * cv * 0.5;
            }
        }
    }

    // UPDATED: Symmetrical High-precision Separable 2D Inverse DCT (DCT-III)
    static void fastIdct8x8(double b[8][8])
    {
        double tmp[8][8];
        static const double pi = std::acos(-1.0);
        
        // Inverse Columns sequentially
        for (int u = 0; u < 8; ++u) {
            for (int y = 0; y < 8; ++y) {
                double sum = 0.0;
                for (int v = 0; v < 8; ++v) {
                    double cv = (v == 0) ? 1.0 / std::sqrt(2.0) : 1.0;
                    sum += cv * b[u][v] * std::cos((2 * y + 1) * v * pi / 16.0);
                }
                tmp[u][y] = sum * 0.5;
            }
        }
        // Inverse Rows sequentially
        for (int x = 0; x < 8; ++x) {
            for (int y = 0; y < 8; ++y) {
                double sum = 0.0;
                for (int u = 0; u < 8; ++u) {
                    double cu = (u == 0) ? 1.0 / std::sqrt(2.0) : 1.0;
                    sum += cu * tmp[u][y] * std::cos((2 * x + 1) * u * pi / 16.0);
                }
                b[x][y] = sum * 0.5;
            }
        }
    }

    static CImg<double> extractLuma(const CImg<unsigned char>& img)
    {
        CImg<double> luma(img.width(), img.height(), 1, 1);
        if (img.spectrum() == 1) {
            cimg_forXY(img, x, y) luma(x, y) = static_cast<double>(img(x, y));
        } else {
            cimg_forXY(img, x, y)
                luma(x, y) = 0.299 * img(x,y,0,0)
                           + 0.587 * img(x,y,0,1)
                           + 0.114 * img(x,y,0,2);
        }
        return luma;
    }

    // UPDATED: Fixed truncation noise by using safe pixel-rounding matrix layers
    static CImg<unsigned char> writeLuma(const CImg<unsigned char>& orig,
                                          const CImg<double>& luma)
    {
        CImg<unsigned char> out = orig;
        cimg_forXY(out, x, y) {
            double val = std::round(std::max(0.0, std::min(255.0, luma(x, y))));
            unsigned char pixel_val = static_cast<unsigned char>(val);
            for (int c = 0; c < out.spectrum(); ++c) {
                out(x, y, 0, c) = pixel_val;
            }
        }
        return out;
    }

    static void readBlock(const CImg<double>& img, int bx, int by, double blk[8][8])
    {
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 8; ++x)
                blk[x][y] = img(bx * 8 + x, by * 8 + y);
    }

    static void writeBlock(CImg<double>& img, int bx, int by, const double blk[8][8])
    {
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 8; ++x)
                img(bx * 8 + x, by * 8 + y) =
                    std::max(0.0, std::min(255.0, blk[x][y]));
    }

    static CImg<unsigned char> loadImageStb(const std::string& path)
    {
        int w = 0, h = 0, channels = 0;
        const int desiredChannels = 3;
        unsigned char* px = stbi_load(path.c_str(), &w, &h, &channels, desiredChannels);
        if (!px) throw std::runtime_error("stbi_load failed: " + path);
        if (w <= 0 || h <= 0) { stbi_image_free(px); throw std::runtime_error("bad dims"); }

        CImg<unsigned char> img(w, h, 1, desiredChannels);
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                const int base = (y * w + x) * desiredChannels;
                for (int c = 0; c < desiredChannels; ++c)
                    img(x, y, 0, c) = px[base + c];
            }
        }
        stbi_image_free(px);
        return img;
    }

    static bool savePng(const std::string& path, const CImg<unsigned char>& img)
    {
        const int W = img.width(), H = img.height(), C = img.spectrum();
        std::vector<unsigned char> buf(static_cast<std::size_t>(W * H * C));
        for (int y = 0; y < H; ++y)
            for (int x = 0; x < W; ++x)
                for (int c = 0; c < C; ++c)
                    buf[static_cast<std::size_t>((y * W + x) * C + c)] = img(x, y, 0, c);
        const int ok = stbi_write_png(path.c_str(), W, H, C, buf.data(), W * C);
        if (!ok) std::cerr << "  [PNG] stbi_write_png failed: " << path << "\n";
        return ok != 0;
    }

    static bool saveImage(const CImg<unsigned char>& img,
                          const std::string& path, ImageFormat fmt)
    {
        try {
            switch (fmt) {
                case ImageFormat::PNG:  return savePng(path, img);
                case ImageFormat::BMP:  img.save_bmp(path.c_str()); return true;
                case ImageFormat::PNM:  img.save_pnm(path.c_str()); return true;
                default:                return savePng(path, img);
            }
        } catch (...) {
            std::cerr << "  [Stego] Cannot save: " << path << "\n";
            return false;
        }
    }

    static std::string hexDump(const std::string& s)
    {
        std::ostringstream o;
        o << std::hex << std::setfill('0');
        for (size_t i = 0; i < std::min(s.size(), size_t(32)); ++i)
            o << std::setw(2) << static_cast<unsigned char>(s[i]);
        if (s.size() > 32) o << "...";
        return o.str();
    }
};

#endif // STEGANOGRAPHY_H