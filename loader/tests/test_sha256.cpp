#include "nl/sha256.h"
#include "nl_test.h"

#include <algorithm>
#include <string>

TEST_CASE("sha256: the FIPS 180-4 example values") {
  CHECK(nl::sha256::of("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  CHECK(nl::sha256::of("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  CHECK(nl::sha256::of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  CHECK(nl::sha256::of(std::string(1000000, 'a')) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
}

TEST_CASE("sha256: updates in pieces give the one-call digest; a finished hash is closed") {
  const std::string text = "The quick brown fox jumps over the lazy dog";
  for (const std::size_t piece : {std::size_t{1}, std::size_t{3}, std::size_t{7}, std::size_t{64}}) {
    nl::sha256::Hasher hasher;
    for (std::size_t at = 0; at < text.size(); at += piece) hasher.update(text.data() + at, std::min(piece, text.size() - at));
    CHECK(hasher.finish_hex() == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592");
  }
  nl::sha256::Hasher once;
  once.update(text.data(), text.size());
  CHECK(nl::sha256::to_hex(once.finish()) == nl::sha256::of(text));
  CHECK_THROWS_AS(once.finish(), nl::sha256::Error);
  CHECK_THROWS_AS(once.update("x", 1), nl::sha256::Error);
}
