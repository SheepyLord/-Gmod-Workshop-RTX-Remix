#include "nl/sha256.h"

#include <windows.h>
#include <bcrypt.h>

#include <algorithm>
#include <cstdio>

namespace nl::sha256 {

namespace {

using OpenProvider = NTSTATUS(WINAPI*)(BCRYPT_ALG_HANDLE*, LPCWSTR, LPCWSTR, ULONG);
using CreateHash = NTSTATUS(WINAPI*)(BCRYPT_ALG_HANDLE, BCRYPT_HASH_HANDLE*, PUCHAR, ULONG, PUCHAR, ULONG, ULONG);
using HashData = NTSTATUS(WINAPI*)(BCRYPT_HASH_HANDLE, PUCHAR, ULONG, ULONG);
using FinishHash = NTSTATUS(WINAPI*)(BCRYPT_HASH_HANDLE, PUCHAR, ULONG, ULONG);
using DestroyHash = NTSTATUS(WINAPI*)(BCRYPT_HASH_HANDLE);

std::string failed(const char* call, NTSTATUS status) {
  char text[96];
  std::snprintf(text, sizeof(text), "%s failed (NTSTATUS 0x%08lX)", call, static_cast<unsigned long>(status));
  return text;
}

// The CNG entry points and the SHA-256 provider: set up once per process, never released.
struct Api {
  CreateHash create = nullptr;
  HashData hash = nullptr;
  FinishHash finish = nullptr;
  DestroyHash destroy = nullptr;
  BCRYPT_ALG_HANDLE provider = nullptr;
  std::string error;  // why there is no provider
};

const Api& api() {
  static const Api instance = [] {
    Api a;
    const HMODULE dll = LoadLibraryExW(L"bcrypt.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!dll) {
      a.error = "cannot load bcrypt.dll from System32 (Windows error " + std::to_string(GetLastError()) + ")";
      return a;
    }
    const auto open = reinterpret_cast<OpenProvider>(GetProcAddress(dll, "BCryptOpenAlgorithmProvider"));
    a.create = reinterpret_cast<CreateHash>(GetProcAddress(dll, "BCryptCreateHash"));
    a.hash = reinterpret_cast<HashData>(GetProcAddress(dll, "BCryptHashData"));
    a.finish = reinterpret_cast<FinishHash>(GetProcAddress(dll, "BCryptFinishHash"));
    a.destroy = reinterpret_cast<DestroyHash>(GetProcAddress(dll, "BCryptDestroyHash"));
    if (!open || !a.create || !a.hash || !a.finish || !a.destroy) {
      a.error = "bcrypt.dll lacks the CNG hash functions";
      return a;
    }
    const NTSTATUS status = open(&a.provider, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    if (!BCRYPT_SUCCESS(status)) {
      a.provider = nullptr;
      a.error = failed("BCryptOpenAlgorithmProvider(SHA256)", status);
    }
    return a;
  }();
  return instance;
}

}  // namespace

Hasher::Hasher() {
  const Api& a = api();
  if (!a.provider) throw Error(a.error);
  BCRYPT_HASH_HANDLE handle = nullptr;
  // No object buffer: CNG allocates the hash state itself (Windows 7 and later).
  const NTSTATUS status = a.create(a.provider, &handle, nullptr, 0, nullptr, 0, 0);
  if (!BCRYPT_SUCCESS(status)) throw Error(failed("BCryptCreateHash", status));
  handle_ = handle;
}

Hasher::~Hasher() {
  if (handle_) api().destroy(handle_);
}

void Hasher::update(const void* data, std::size_t size) {
  if (!handle_) throw Error("SHA-256 hash updated after finish()");
  auto* bytes = static_cast<PUCHAR>(const_cast<void*>(data));
  while (size) {
    const ULONG n = static_cast<ULONG>(std::min<std::size_t>(size, std::size_t{1} << 30));
    const NTSTATUS status = api().hash(handle_, bytes, n, 0);
    if (!BCRYPT_SUCCESS(status)) throw Error(failed("BCryptHashData", status));
    bytes += n;
    size -= n;
  }
}

Digest Hasher::finish() {
  if (!handle_) throw Error("SHA-256 hash finished twice");
  Digest digest{};
  const NTSTATUS status = api().finish(handle_, digest.data(), static_cast<ULONG>(digest.size()), 0);
  api().destroy(handle_);
  handle_ = nullptr;
  if (!BCRYPT_SUCCESS(status)) throw Error(failed("BCryptFinishHash", status));
  return digest;
}

std::string Hasher::finish_hex() {
  return to_hex(finish());
}

std::string to_hex(const Digest& digest) {
  static constexpr char kHex[] = "0123456789abcdef";
  std::string out;
  out.reserve(digest.size() * 2);
  for (const std::uint8_t b : digest) {
    out.push_back(kHex[b >> 4]);
    out.push_back(kHex[b & 0xF]);
  }
  return out;
}

std::string of(std::string_view bytes) {
  Hasher hasher;
  hasher.update(bytes.data(), bytes.size());
  return hasher.finish_hex();
}

}  // namespace nl::sha256
