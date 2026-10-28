#include "nl/lzma.h"

#include "LzmaDec.h"

#include <algorithm>
#include <cstdlib>
#include <new>
#include <string>
#include <vector>

namespace nl::lzma {

namespace {

constexpr unsigned kMaxProperties = 9 * 5 * 5;  // lc < 9, lp < 5, pb < 5

void* allocate(ISzAllocPtr, size_t size) {
  return std::malloc(size);
}

void release(ISzAllocPtr, void* address) {
  std::free(address);
}

const ISzAlloc kAllocator = {allocate, release};

}  // namespace

Header parse_header(const unsigned char* bytes, std::size_t size, const Limits& limits) {
  if (size < kHeaderSize) throw gma::FormatError("truncated LZMA header");
  Header header;
  header.properties = bytes[0];
  if (header.properties >= kMaxProperties) throw gma::FormatError("invalid LZMA properties");
  for (int i = 3; i >= 0; --i) header.dictionary_size = header.dictionary_size << 8 | bytes[1 + i];
  for (int i = 7; i >= 0; --i) header.uncompressed_size = header.uncompressed_size << 8 | bytes[5 + i];
  if (header.dictionary_size > limits.max_dictionary_size) {
    throw gma::FormatError("LZMA dictionary of " + std::to_string(header.dictionary_size) +
                           " bytes exceeds the " + std::to_string(limits.max_dictionary_size) + "-byte limit");
  }
  return header;
}

struct Source::Impl {
  std::unique_ptr<gma::Source> in;
  Header header;
  CLzmaDec state{};
  std::vector<unsigned char> input = std::vector<unsigned char>(64 * 1024);
  std::size_t in_pos = 0;
  std::size_t in_end = 0;
  bool input_eof = false;
  std::uint64_t produced = 0;
  bool finished = false;
  bool gmod_footer = false;
  bool pending_error = false;  // damage found after some bytes of the last step were decoded

  Impl() { LzmaDec_Construct(&state); }
  ~Impl() { LzmaDec_Free(&state, &kAllocator); }

  void refill() {
    in_pos = 0;
    in_end = in->read(input.data(), input.size());
    if (in_end == 0) input_eof = true;
  }

  // Runs the decoder on the buffered input; returns bytes written to `out`.
  std::size_t step(unsigned char* out, std::size_t out_size, ELzmaFinishMode mode, ELzmaStatus& status) {
    SizeT dest_len = out_size;
    SizeT src_len = in_end - in_pos;
    unsigned char unused = 0;
    const SRes result = LzmaDec_DecodeToBuf(&state, out ? out : &unused, &dest_len, input.data() + in_pos, &src_len,
                                            mode, &status);
    in_pos += src_len;
    produced += dest_len;
    if (result != SZ_OK) {
      // Hand over what was decoded before the damage; the next read reports it.
      if (dest_len == 0) throw gma::FormatError("corrupt LZMA data");
      pending_error = true;
    }
    return dest_len;
  }

  // Called once the declared size has been produced: an end marker may follow, nothing else may.
  void finish_known_size() {
    for (;;) {
      ELzmaStatus status = LZMA_STATUS_NOT_SPECIFIED;
      try {
        step(nullptr, 0, LZMA_FINISH_END, status);
      } catch (const gma::FormatError&) {
        throw gma::FormatError("LZMA stream continues past its declared size");
      }
      if (status == LZMA_STATUS_FINISHED_WITH_MARK || status == LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK) break;
      if (status == LZMA_STATUS_NEEDS_MORE_INPUT && !input_eof) {
        if (in_pos == in_end) refill();
        if (!input_eof) continue;
      }
      throw gma::FormatError("LZMA stream does not end at its declared size");
    }
    finish_input();
  }

  // After the stream: nothing, or exactly GMod's 8-byte footer (32-bit size, then 0xBEEFCACE).
  void finish_input() {
    std::string tail(reinterpret_cast<const char*>(input.data() + in_pos), in_end - in_pos);
    std::uint64_t trailing = tail.size();
    while (!input_eof) {
      refill();
      trailing += in_end;
      if (tail.size() <= kGmodFooterSize) tail.append(reinterpret_cast<const char*>(input.data()), in_end);
    }
    in_pos = in_end;
    if (trailing == kGmodFooterSize) {
      const auto le32 = [&tail](std::size_t at) {
        return static_cast<std::uint32_t>(static_cast<unsigned char>(tail[at])) |
               static_cast<std::uint32_t>(static_cast<unsigned char>(tail[at + 1])) << 8 |
               static_cast<std::uint32_t>(static_cast<unsigned char>(tail[at + 2])) << 16 |
               static_cast<std::uint32_t>(static_cast<unsigned char>(tail[at + 3])) << 24;
      };
      if (le32(4) == kGmodFooterMagic) {
        if (le32(0) != static_cast<std::uint32_t>(produced)) {
          throw gma::FormatError("GMod LZMA footer: size " + std::to_string(le32(0)) + " does not match " +
                                 std::to_string(produced) + " decoded bytes");
        }
        gmod_footer = true;
        finished = true;
        return;
      }
    }
    if (trailing) throw gma::FormatError("trailing data after the LZMA stream (" + std::to_string(trailing) + " bytes)");
    finished = true;
  }
};

Source::Source(std::unique_ptr<gma::Source> compressed, const Limits& limits) : impl_(std::make_unique<Impl>()) {
  impl_->in = std::move(compressed);
  unsigned char raw[kHeaderSize];
  std::size_t have = 0;
  while (have < kHeaderSize) {
    const std::size_t n = impl_->in->read(raw + have, kHeaderSize - have);
    if (!n) throw gma::FormatError("truncated LZMA header");
    have += n;
  }
  impl_->header = parse_header(raw, have, limits);
  const SRes result = LzmaDec_Allocate(&impl_->state, raw, LZMA_PROPS_SIZE, &kAllocator);
  if (result == SZ_ERROR_MEM) throw std::bad_alloc();
  if (result != SZ_OK) throw gma::FormatError("unsupported LZMA properties");
  LzmaDec_Init(&impl_->state);
}

Source::~Source() = default;

const Header& Source::header() const noexcept {
  return impl_->header;
}

std::uint64_t Source::produced() const noexcept {
  return impl_->produced;
}

bool Source::gmod_footer() const noexcept {
  return impl_->gmod_footer;
}

std::size_t Source::read(void* buffer, std::size_t size) {
  Impl& s = *impl_;
  if (s.pending_error) throw gma::FormatError("corrupt LZMA data");
  if (s.finished || size == 0) return 0;
  if (s.header.size_known()) {
    const std::uint64_t left = s.header.uncompressed_size - s.produced;
    if (left == 0) {
      s.finish_known_size();
      return 0;
    }
    size = static_cast<std::size_t>(std::min<std::uint64_t>(size, left));
  }
  auto* out = static_cast<unsigned char*>(buffer);
  std::size_t got = 0;
  while (got < size) {
    if (s.in_pos == s.in_end && !s.input_eof) s.refill();
    ELzmaStatus status = LZMA_STATUS_NOT_SPECIFIED;
    const std::size_t consumed_before = s.in_pos;
    const std::size_t n = s.step(out + got, size - got, LZMA_FINISH_ANY, status);
    got += n;
    if (status == LZMA_STATUS_FINISHED_WITH_MARK) {
      if (s.header.size_known() && s.produced != s.header.uncompressed_size) {
        throw gma::FormatError("LZMA stream ends before its declared size");
      }
      s.finish_input();
      break;
    }
    if (n == 0 && s.in_pos == consumed_before) {
      if (s.input_eof) throw gma::FormatError("truncated LZMA stream");
      if (s.in_pos != s.in_end) throw gma::FormatError("corrupt LZMA data (decoder made no progress)");
    }
    // A step decodes all it can from the buffered input, so return what it produced rather than
    // reading further: damage past the bytes a caller needs (an index, say) must not fail them.
    if (got > 0) break;
  }
  return got;
}

}  // namespace nl::lzma
