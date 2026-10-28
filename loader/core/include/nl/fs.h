#pragma once
// File-system access for the deployer. Every change it makes to the disk goes through a FileSystem,
// so tests can count, fail or interrupt any single change (fault injection, docs/TESTING.md); reads
// and checks are free functions. Every Win32 call uses the extended-length (\\?\) form of the path,
// so deep package paths work, and nothing here follows a link.

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace nl::fs {

using Path = std::filesystem::path;

// A file-system call failed; code() is the Windows error (0 if none applies).
class Error : public std::runtime_error {
 public:
  Error(const std::string& what, unsigned long code) : std::runtime_error(what), code_(code) {}
  unsigned long code() const noexcept { return code_; }

 private:
  unsigned long code_;
};

// A new file being written. close() flushes it to disk and closes it; a writer destroyed without
// close() only closes the handle.
class Writer {
 public:
  virtual ~Writer() = default;
  virtual void write(const void* data, std::size_t size) = 0;
  virtual void close() = 0;
};

class FileSystem {
 public:
  virtual ~FileSystem() = default;
  virtual void create_directory(const Path& dir) = 0;  // the parent must exist; fails if it exists
  virtual void remove_directory(const Path& dir) = 0;  // must be empty
  virtual void remove_file(const Path& file) = 0;
  // Renames a file or folder within its volume (never copies), write-through. With `replace` a file
  // may replace an existing file, atomically.
  virtual void move(const Path& from, const Path& to, bool replace) = 0;
  virtual std::unique_ptr<Writer> create_file(const Path& file) = 0;  // fails if it exists
};

// The real file system. While another process has a file open (typically an antivirus scanner
// looking at a new DLL) it retries for about two seconds.
FileSystem& win32();

// Counts every change it passes to `inner` (writes and closes included). `before(n, what)` runs
// just before change n (from 1) is made and may throw to make it fail, or end the process.
class Counting final : public FileSystem {
 public:
  using Hook = std::function<void(std::uint64_t change, std::string_view what)>;
  explicit Counting(FileSystem& inner, Hook before = {});
  std::uint64_t operations() const noexcept { return count_; }
  void note(std::string_view what);  // counts one change (used by the writers it hands out)

  void create_directory(const Path& dir) override;
  void remove_directory(const Path& dir) override;
  void remove_file(const Path& file) override;
  void move(const Path& from, const Path& to, bool replace) override;
  std::unique_ptr<Writer> create_file(const Path& file) override;

 private:
  FileSystem& inner_;
  Hook before_;
  std::uint64_t count_ = 0;
};

// Writes `bytes` to `file`: a temporary file beside it (a stale one is removed first), flushed, then
// moved over the target, so a reader sees the old or the new content, never a mix.
void write_atomic(FileSystem& disk, const Path& file, std::string_view bytes);

// Deletes `dir` and everything below it. Links inside are removed, never followed.
void remove_tree(FileSystem& disk, const Path& dir);

struct Stat {
  bool exists = false;
  bool directory = false;
  bool link = false;        // a reparse point: junction, symbolic link, ...
  std::uint64_t size = 0;
  std::uint64_t mtime = 0;  // last write time in 100 ns units since 1601 (FILETIME)
};
// Never follows links. A missing path gives exists = false; other failures throw Error.
Stat stat(const Path& path);

struct Hash {
  std::string sha256;  // hex
  std::uint64_t size = 0;
};
// SHA-256 of a file's contents, read with full sharing. Links and folders are refused.
Hash hash_file(const Path& file);

struct Item {
  std::wstring name;
  bool directory = false;
  bool link = false;
};
std::vector<Item> list(const Path& dir);  // the folder's entries, not recursive
bool empty_directory(const Path& dir);    // an ordinary folder that holds nothing

std::string read_file(const Path& file, std::size_t max_bytes);  // whole file; throws Error

// `root` joined with a relative '/'-separated UTF-8 path.
Path join(const Path& root, std::string_view relative);

// Throws Error if `root`/`relative` passes through a link at any level below `root`, so a junction
// cannot redirect what the loader writes out of the game folder. Missing components are fine.
void refuse_links(const Path& root, std::string_view relative);

// The \\?\ form of a path, made absolute and normalised, for Win32 calls.
std::wstring long_path(const Path& path);

// UTF-8 text of a path, for messages and the journal.
std::string utf8(const Path& path);

}  // namespace nl::fs
