#include "nl/vdf.h"

#include "nl/paths.h"

#include <fstream>
#include <system_error>

namespace nl::vdf {

namespace {

constexpr std::size_t kMaxDepth = 64;

struct Token {
  std::string text;
  bool quoted = false;
  bool open = false;   // {
  bool close = false;  // }
};

class Tokenizer {
 public:
  explicit Tokenizer(std::string_view text) : text_(text) {}

  bool next(Token& token) {
    for (;;) {
      while (pos_ < text_.size() && is_space(text_[pos_])) ++pos_;
      if (pos_ >= text_.size()) return false;
      if (text_.substr(pos_, 2) == "//") {
        const std::size_t end = text_.find('\n', pos_);
        pos_ = end == std::string_view::npos ? text_.size() : end + 1;
        continue;
      }
      break;
    }
    token = Token{};
    const char c = text_[pos_];
    if (c == '{' || c == '}') {
      token.open = c == '{';
      token.close = c == '}';
      ++pos_;
      return true;
    }
    if (c == '"') {
      token.quoted = true;
      ++pos_;
      while (pos_ < text_.size() && text_[pos_] != '"') {
        if (text_[pos_] == '\\' && pos_ + 1 < text_.size()) {
          const char e = text_[++pos_];
          switch (e) {
            case 'n': token.text.push_back('\n'); break;
            case 't': token.text.push_back('\t'); break;
            case '\\': token.text.push_back('\\'); break;
            case '"': token.text.push_back('"'); break;
            default:
              token.text.push_back('\\');
              token.text.push_back(e);
          }
        } else {
          token.text.push_back(text_[pos_]);
        }
        ++pos_;
      }
      if (pos_ < text_.size()) ++pos_;  // closing quote; a missing one at the end is tolerated
      return true;
    }
    const std::size_t start = pos_;
    while (pos_ < text_.size() && !is_space(text_[pos_]) && text_[pos_] != '{' && text_[pos_] != '}' && text_[pos_] != '"') ++pos_;
    token.text = std::string(text_.substr(start, pos_ - start));
    return true;
  }

 private:
  static bool is_space(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
  std::string_view text_;
  std::size_t pos_ = 0;
};

bool conditional(const Token& t) {
  return !t.quoted && (t.text.rfind("[$", 0) == 0 || t.text.rfind("[!$", 0) == 0);
}

}  // namespace

const Node* Node::find(std::string_view key) const noexcept {
  const std::string wanted = paths::fold(key);
  const Node* match = nullptr;
  for (const auto& [name, node] : children) {
    if (paths::fold(name) == wanted) match = &node;
  }
  return match;
}

Node parse(std::string_view text) {
  if (text.size() > kMaxBytes) throw Error("KeyValues text larger than " + std::to_string(kMaxBytes) + " bytes");
  Node root;
  root.block = true;
  std::vector<Node*> stack{&root};
  std::string key;
  bool have_key = false;
  Tokenizer tokens(text);
  Token t;
  while (tokens.next(t)) {
    if (t.open) {
      if (!have_key) throw Error("KeyValues: '{' without a key");
      if (stack.size() > kMaxDepth) throw Error("KeyValues: nesting deeper than 64");
      Node child;
      child.block = true;
      stack.back()->children.emplace_back(std::move(key), std::move(child));
      stack.push_back(&stack.back()->children.back().second);
      have_key = false;
    } else if (t.close) {
      if (stack.size() == 1) throw Error("KeyValues: unbalanced '}'");
      stack.pop_back();
      have_key = false;
    } else if (conditional(t)) {
      continue;
    } else if (!have_key) {
      key = std::move(t.text);
      have_key = true;
    } else {
      Node leaf;
      leaf.value = std::move(t.text);
      stack.back()->children.emplace_back(std::move(key), std::move(leaf));
      have_key = false;
    }
  }
  if (stack.size() != 1) throw Error("KeyValues: unterminated '{' block");
  return root;
}

Node load(const std::filesystem::path& file) {
  std::error_code ec;
  const auto size = std::filesystem::file_size(file, ec);
  if (ec) throw std::filesystem::filesystem_error("cannot read", file, ec);
  if (size > kMaxBytes) throw Error("KeyValues file larger than " + std::to_string(kMaxBytes) + " bytes");
  std::ifstream in(file, std::ios::binary);
  std::string text(static_cast<std::size_t>(size), '\0');
  if (!in.read(text.data(), static_cast<std::streamsize>(text.size()))) {
    throw std::filesystem::filesystem_error("cannot read", file, std::make_error_code(std::errc::io_error));
  }
  return parse(text);
}

}  // namespace nl::vdf
