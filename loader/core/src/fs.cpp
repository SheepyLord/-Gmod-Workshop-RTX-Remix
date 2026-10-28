#include "nl/fs.h"

#include "nl/sha256.h"

#include <windows.h>

#include <algorithm>
#include <utility>

namespace nl::fs {

namespace {

std::string message(const std::string& what, const Path& path, DWORD code) {
  return what + " " + utf8(path) + " (Windows error " + std::to_string(code) + ")";
}

[[noreturn]] void fail(const std::string& what, const Path& path, DWORD code) {
  throw Error(message(what, path, code), code);
}

// Errors that go away once another process (an antivirus scanner, the indexer) closes the file.
bool transient(DWORD code) {
  return code == ERROR_SHARING_VIOLATION || code == ERROR_LOCK_VIOLATION || code == ERROR_ACCESS_DENIED;
}

// Runs `call` until it succeeds, fails for a lasting reason, or about two seconds have passed.
// Returns 0 on success, otherwise the last Windows error.
template <class Call>
DWORD with_retries(Call&& call) {
  DWORD code = 0;
  for (int attempt = 0; attempt < 12; ++attempt) {
    if (call()) return 0;
    code = GetLastError();
    if (!transient(code)) return code;
    Sleep(attempt < 4 ? 25u << attempt : 250u);
  }
  return code;
}

struct Handle {
  HANDLE value = INVALID_HANDLE_VALUE;
  ~Handle() {
    if (value != INVALID_HANDLE_VALUE) CloseHandle(value);
  }
};

class Win32Writer final : public Writer {
 public:
  Win32Writer(HANDLE handle, Path path) : handle_(handle), path_(std::move(path)) {}
  ~Win32Writer() override {
    if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
  }
  Win32Writer(const Win32Writer&) = delete;
  Win32Writer& operator=(const Win32Writer&) = delete;

  void write(const void* data, std::size_t size) override {
    const auto* bytes = static_cast<const unsigned char*>(data);
    while (size) {
      const DWORD chunk = static_cast<DWORD>(std::min<std::size_t>(size, std::size_t{1} << 30));
      DWORD written = 0;
      if (!WriteFile(handle_, bytes, chunk, &written, nullptr) || written == 0) fail("cannot write", path_, GetLastError());
      bytes += written;
      size -= written;
    }
  }

  void close() override {
    if (handle_ == INVALID_HANDLE_VALUE) return;
    const BOOL flushed = FlushFileBuffers(handle_);
    const DWORD code = flushed ? 0 : GetLastError();
    CloseHandle(handle_);
    handle_ = INVALID_HANDLE_VALUE;
    if (!flushed) fail("cannot flush", path_, code);
  }

 private:
  HANDLE handle_;
  Path path_;
};

class Win32 final : public FileSystem {
 public:
  void create_directory(const Path& dir) override {
    if (!CreateDirectoryW(long_path(dir).c_str(), nullptr)) fail("cannot create folder", dir, GetLastError());
  }

  void remove_directory(const Path& dir) override {
    const std::wstring path = long_path(dir);
    if (const DWORD code = with_retries([&] { return RemoveDirectoryW(path.c_str()) != 0; })) fail("cannot remove folder", dir, code);
  }

  void remove_file(const Path& file) override {
    const std::wstring path = long_path(file);
    if (const DWORD code = with_retries([&] { return DeleteFileW(path.c_str()) != 0; })) fail("cannot delete", file, code);
  }

  void move(const Path& from, const Path& to, bool replace) override {
    const std::wstring source = long_path(from);
    const std::wstring target = long_path(to);
    const DWORD flags = replace ? MOVEFILE_WRITE_THROUGH | MOVEFILE_REPLACE_EXISTING : MOVEFILE_WRITE_THROUGH;
    if (const DWORD code = with_retries([&] { return MoveFileExW(source.c_str(), target.c_str(), flags) != 0; })) {
      throw Error(message("cannot move " + utf8(from) + " to", to, code), code);
    }
  }

  std::unique_ptr<Writer> create_file(const Path& file) override {
    const HANDLE handle =
        CreateFileW(long_path(file).c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle == INVALID_HANDLE_VALUE) fail("cannot create", file, GetLastError());
    return std::make_unique<Win32Writer>(handle, file);
  }
};

class CountingWriter final : public Writer {
 public:
  CountingWriter(Counting& owner, std::unique_ptr<Writer> inner) : owner_(&owner), inner_(std::move(inner)) {}
  void write(const void* data, std::size_t size) override {
    owner_->note("write");
    inner_->write(data, size);
  }
  void close() override {
    owner_->note("close");
    inner_->close();
  }

 private:
  Counting* owner_;
  std::unique_ptr<Writer> inner_;
};

}  // namespace

FileSystem& win32() {
  static Win32 instance;
  return instance;
}

Counting::Counting(FileSystem& inner, Hook before) : inner_(inner), before_(std::move(before)) {}

void Counting::note(std::string_view what) {
  ++count_;
  if (before_) before_(count_, what);
}

void Counting::create_directory(const Path& dir) {
  note("create_directory");
  inner_.create_directory(dir);
}

void Counting::remove_directory(const Path& dir) {
  note("remove_directory");
  inner_.remove_directory(dir);
}

void Counting::remove_file(const Path& file) {
  note("remove_file");
  inner_.remove_file(file);
}

void Counting::move(const Path& from, const Path& to, bool replace) {
  note("move");
  inner_.move(from, to, replace);
}

std::unique_ptr<Writer> Counting::create_file(const Path& file) {
  note("create_file");
  return std::make_unique<CountingWriter>(*this, inner_.create_file(file));
}

void write_atomic(FileSystem& disk, const Path& file, std::string_view bytes) {
  Path temp = file;
  temp += L".tmp";
  if (stat(temp).exists) disk.remove_file(temp);  // left by an interrupted earlier write
  {
    const auto writer = disk.create_file(temp);
    writer->write(bytes.data(), bytes.size());
    writer->close();
  }
  disk.move(temp, file, true);
}

void remove_tree(FileSystem& disk, const Path& dir) {
  for (const Item& item : list(dir)) {
    const Path child = dir / item.name;
    if (item.directory && !item.link) {
      remove_tree(disk, child);
    } else if (item.directory) {
      disk.remove_directory(child);  // a junction or directory link: removes the link only
    } else {
      disk.remove_file(child);
    }
  }
  disk.remove_directory(dir);
}

Stat stat(const Path& path) {
  Stat s;
  WIN32_FILE_ATTRIBUTE_DATA data{};
  if (!GetFileAttributesExW(long_path(path).c_str(), GetFileExInfoStandard, &data)) {
    const DWORD code = GetLastError();
    if (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND) return s;
    fail("cannot read the attributes of", path, code);
  }
  s.exists = true;
  s.directory = (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
  s.link = (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
  s.readonly = (data.dwFileAttributes & FILE_ATTRIBUTE_READONLY) != 0;
  s.size = std::uint64_t{data.nFileSizeHigh} << 32 | data.nFileSizeLow;
  s.mtime = std::uint64_t{data.ftLastWriteTime.dwHighDateTime} << 32 | data.ftLastWriteTime.dwLowDateTime;
  return s;
}

namespace {

// Opens an existing file for reading with full sharing, refusing links and folders.
HANDLE open_for_reading(const Path& file) {
  const HANDLE handle = CreateFileW(long_path(file).c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                    nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (handle == INVALID_HANDLE_VALUE) fail("cannot open", file, GetLastError());
  BY_HANDLE_FILE_INFORMATION info{};
  if (!GetFileInformationByHandle(handle, &info)) {
    const DWORD code = GetLastError();
    CloseHandle(handle);
    fail("cannot read", file, code);
  }
  if (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) {
    CloseHandle(handle);
    throw Error(utf8(file) + " is a link or a folder, not a file", 0);
  }
  return handle;
}

}  // namespace

Hash hash_file(const Path& file) {
  const Handle handle{open_for_reading(file)};
  sha256::Hasher hasher;
  std::vector<unsigned char> buffer(std::size_t{1} << 20);
  Hash out;
  for (;;) {
    DWORD got = 0;
    if (!ReadFile(handle.value, buffer.data(), static_cast<DWORD>(buffer.size()), &got, nullptr)) {
      fail("cannot read", file, GetLastError());
    }
    if (got == 0) break;
    hasher.update(buffer.data(), got);
    out.size += got;
  }
  out.sha256 = hasher.finish_hex();
  return out;
}

std::vector<Item> list(const Path& dir) {
  std::vector<Item> items;
  std::wstring pattern = long_path(dir);
  if (pattern.back() != L'\\') pattern += L'\\';
  pattern += L'*';
  WIN32_FIND_DATAW data{};
  const HANDLE find = FindFirstFileExW(pattern.c_str(), FindExInfoBasic, &data, FindExSearchNameMatch, nullptr,
                                       FIND_FIRST_EX_LARGE_FETCH);
  if (find == INVALID_HANDLE_VALUE) {
    const DWORD code = GetLastError();
    if (code == ERROR_FILE_NOT_FOUND) return items;
    fail("cannot list", dir, code);
  }
  do {
    const std::wstring name = data.cFileName;
    if (name == L"." || name == L"..") continue;
    items.push_back({name, (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0,
                     (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0});
  } while (FindNextFileW(find, &data));
  const DWORD code = GetLastError();
  FindClose(find);
  if (code != ERROR_NO_MORE_FILES) fail("cannot list", dir, code);
  return items;
}

bool empty_directory(const Path& dir) {
  const Stat s = stat(dir);
  return s.exists && s.directory && !s.link && list(dir).empty();
}

std::string read_file(const Path& file, std::size_t max_bytes) {
  const Handle handle{open_for_reading(file)};
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(handle.value, &size)) fail("cannot read the size of", file, GetLastError());
  if (static_cast<std::uint64_t>(size.QuadPart) > max_bytes) {
    throw Error(utf8(file) + " is larger than " + std::to_string(max_bytes) + " bytes", 0);
  }
  std::string bytes(static_cast<std::size_t>(size.QuadPart), '\0');
  std::size_t have = 0;
  while (have < bytes.size()) {
    DWORD got = 0;
    const DWORD want = static_cast<DWORD>(std::min<std::size_t>(bytes.size() - have, std::size_t{1} << 30));
    if (!ReadFile(handle.value, bytes.data() + have, want, &got, nullptr)) fail("cannot read", file, GetLastError());
    if (got == 0) throw Error(utf8(file) + " became shorter while it was read", 0);
    have += got;
  }
  return bytes;
}

Path join(const Path& root, std::string_view relative) {
  return root / Path(std::u8string(reinterpret_cast<const char8_t*>(relative.data()), relative.size()));
}

void refuse_links(const Path& root, std::string_view relative) {
  Path current = root;
  std::size_t start = 0;
  for (;;) {
    const std::size_t slash = relative.find('/', start);
    current = join(current, relative.substr(start, slash == std::string_view::npos ? std::string_view::npos : slash - start));
    const Stat s = stat(current);
    if (!s.exists) return;
    if (s.link) throw Error(utf8(current) + " is a link or junction; the loader does not write through links", 0);
    if (slash == std::string_view::npos) return;
    start = slash + 1;
  }
}

std::wstring long_path(const Path& path) {
  std::wstring text = std::filesystem::absolute(path).lexically_normal().native();
  while (text.size() > 3 && text.back() == L'\\') text.pop_back();
  if (text.rfind(L"\\\\?\\", 0) == 0) return text;
  if (text.rfind(L"\\\\", 0) == 0) return L"\\\\?\\UNC\\" + text.substr(2);
  return L"\\\\?\\" + text;
}

std::string utf8(const Path& path) {
  const std::u8string text = path.u8string();
  return std::string(text.begin(), text.end());
}

}  // namespace nl::fs
