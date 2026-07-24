// C ABI shim over the vendored RE2 engine. RE2 matches on UTF-8 bytes and
// returns byte offsets; the Dart side works in that byte space and converts
// back to UTF-16 string indices. Every entry point is `extern "C"` and takes
// explicit lengths (never NUL-terminated), so embedded NULs and binary text
// pass through unharmed. No C++ exception is allowed to cross the boundary:
// every entry point that runs code able to throw -- a match, a compile, an
// allocation -- wraps its body in `try`/`catch (...)` and reports failure
// through its return value, exactly as the blake3_ffi and simdjson_dart shims
// do. The rest carry no `catch` because nothing in them can throw: they are
// accessors that read a non-throwing RE2 getter behind a null check, and
// deallocators that call `std::free` or `delete`.

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <map>
#include <new>
#include <string>
#include <vector>

// MSVC exports nothing from a DLL by default; ELF/Mach-O may be built with
// hidden visibility. Mark the C ABI entry points exported explicitly so
// @Native can resolve them. RE2's own C++ symbols stay internal to the DLL.
#if defined(_WIN32)
#define RE2_EXPORT __declspec(dllexport)
#else
#define RE2_EXPORT __attribute__((visibility("default")))
#endif

#include "re2/re2.h"
#include "re2/set.h"

using re2::StringPiece;

extern "C" {

// Compiles `pattern` (UTF-8, `pattern_len` bytes) and returns an owning
// handle. The handle is always non-null on success; on allocation failure it
// is null. A pattern RE2 rejects (backreferences, lookaround, bad syntax)
// still returns a handle whose re2_ok() is 0 and whose re2_error() explains
// why, so the Dart side can raise a FormatException.
//
// `multi_line` is applied by prepending the (?m) flag rather than through an
// Options field, because in RE2's default (non-POSIX) syntax the one_line
// option is ignored; (?m) is the documented way to make ^ and $ match at
// line boundaries.
RE2_EXPORT void* re2_compile(const char* pattern, int32_t pattern_len,
                             int32_t case_sensitive, int32_t multi_line,
                             int32_t dot_all, int64_t max_mem) {
  try {
    RE2::Options options;
    options.set_log_errors(false);
    if (case_sensitive == 0) options.set_case_sensitive(false);
    if (dot_all != 0) options.set_dot_nl(true);
    // A non-positive value keeps RE2's own default budget. A positive one caps
    // the compiled program's memory, so a pattern that would expand into an
    // oversized automaton fails to compile (re2_ok() == 0) instead of
    // allocating unboundedly, which is the guard against a hostile pattern.
    if (max_mem > 0) options.set_max_mem(max_mem);

    std::string source;
    if (multi_line != 0) source.append("(?m)");
    source.append(pattern, static_cast<size_t>(pattern_len));

    return static_cast<void*>(
        new (std::nothrow) RE2(StringPiece(source.data(), source.size()),
                               options));
  } catch (...) {
    return nullptr;
  }
}

// Escapes `text` so that, read as a pattern, it matches that exact string and
// nothing is treated as a metacharacter. Writes the result into `out` (up to
// `out_cap` bytes) and returns the full escaped length; if that length exceeds
// `out_cap` the caller retries with a larger buffer. A NULL `out` (or zero
// capacity) just measures. Worst case is 2x the input plus a NUL, so a caller
// can size the buffer up front.
RE2_EXPORT int32_t re2_quote_meta(const char* text, int32_t text_len,
                                  char* out, int32_t out_cap) {
  try {
    const std::string quoted =
        RE2::QuoteMeta(StringPiece(text, static_cast<size_t>(text_len)));
    const int32_t len = static_cast<int32_t>(quoted.size());
    if (out != nullptr && out_cap > 0) {
      const int32_t n = len < out_cap ? len : out_cap - 1;
      if (n > 0) std::memcpy(out, quoted.data(), static_cast<size_t>(n));
      out[n] = '\0';
    }
    return len;
  } catch (...) {
    return -1;
  }
}

// 1 if the pattern compiled cleanly, 0 otherwise (including a null handle).
RE2_EXPORT int32_t re2_ok(void* handle) {
  if (handle == nullptr) return 0;
  return static_cast<RE2*>(handle)->ok() ? 1 : 0;
}

// The compile error message, valid until the handle is freed. The bytes are
// exactly those RE2's own RegexpStatus::Text() produced, which can embed a
// NUL (it may quote a slice of the original pattern, and this shim accepts
// patterns with embedded NULs). The buffer happens to carry a trailing NUL
// for convenience, but a caller must not rely on it as the terminator; pair
// this with re2_error_length() and read exactly that many bytes.
RE2_EXPORT const char* re2_error(void* handle) {
  if (handle == nullptr) return "out of memory";
  return static_cast<RE2*>(handle)->error().c_str();
}

// The exact byte length of the message re2_error() returns for the same
// handle, so the caller never has to scan for a NUL terminator that may
// appear before the message actually ends.
RE2_EXPORT int32_t re2_error_length(void* handle) {
  if (handle == nullptr) return static_cast<int32_t>(std::strlen("out of memory"));
  return static_cast<int32_t>(static_cast<RE2*>(handle)->error().size());
}

// Number of capturing groups, excluding the whole match (group 0). Returns
// -1 for a null handle.
RE2_EXPORT int32_t re2_num_groups(void* handle) {
  if (handle == nullptr) return -1;
  return static_cast<int32_t>(
      static_cast<RE2*>(handle)->NumberOfCapturingGroups());
}

// 1 if the pattern matches anywhere in `text`, else 0. Cheaper than
// re2_match: no submatch bookkeeping.
RE2_EXPORT int32_t re2_partial_match(void* handle, const char* text,
                                     int32_t text_len) {
  if (handle == nullptr) return 0;
  try {
    return RE2::PartialMatch(StringPiece(text, static_cast<size_t>(text_len)),
                             *static_cast<RE2*>(handle))
               ? 1
               : 0;
  } catch (...) {
    return 0;
  }
}

// Finds the leftmost match at or after byte offset `startpos`. On a match,
// writes byte offsets for groups 0..N into out_starts/out_ends (an unmatched
// optional group is written as -1/-1) and returns 1. Returns 0 when there is
// no match and -1 on error. `max_slots` caps how many group slots are filled.
RE2_EXPORT int32_t re2_match(void* handle, const char* text, int32_t text_len,
                             int32_t startpos, int32_t* out_starts,
                             int32_t* out_ends, int32_t max_slots) {
  if (handle == nullptr) return -1;
  try {
    RE2* re = static_cast<RE2*>(handle);
    const int groups = re->NumberOfCapturingGroups();
    if (groups < 0) return -1;

    int slots = groups + 1;
    if (slots > max_slots) slots = max_slots;

    std::vector<StringPiece> submatch(static_cast<size_t>(slots));
    const StringPiece input(text, static_cast<size_t>(text_len));
    const bool matched = re->Match(
        input, static_cast<size_t>(startpos), static_cast<size_t>(text_len),
        RE2::UNANCHORED, submatch.data(), slots);
    if (!matched) return 0;

    for (int i = 0; i < slots; ++i) {
      if (submatch[i].data() == nullptr) {
        out_starts[i] = -1;
        out_ends[i] = -1;
      } else {
        const int32_t begin = static_cast<int32_t>(submatch[i].data() - text);
        out_starts[i] = begin;
        out_ends[i] = begin + static_cast<int32_t>(submatch[i].size());
      }
    }
    return 1;
  } catch (...) {
    return -1;
  }
}

// Number of named capturing groups.
RE2_EXPORT int32_t re2_num_named_groups(void* handle) {
  if (handle == nullptr) return 0;
  try {
    return static_cast<int32_t>(
        static_cast<RE2*>(handle)->NamedCapturingGroups().size());
  } catch (...) {
    return 0;
  }
}

// Writes the name of the i-th named group (NUL-terminated) into `name_buf`
// (capacity `cap` bytes) and its group index into *out_index. Returns the
// full name length in bytes, or -1 if `i` is out of range. If the name does
// not fit it is truncated but the return value is still the full length, so
// the caller can retry with a larger buffer.
RE2_EXPORT int32_t re2_named_group_at(void* handle, int32_t index,
                                      char* name_buf, int32_t cap,
                                      int32_t* out_index) {
  if (handle == nullptr) return -1;
  try {
    const std::map<std::string, int>& groups =
        static_cast<RE2*>(handle)->NamedCapturingGroups();
    if (index < 0 || index >= static_cast<int32_t>(groups.size())) return -1;

    auto it = groups.begin();
    std::advance(it, index);
    const int32_t length = static_cast<int32_t>(it->first.size());
    if (cap > 0) {
      int32_t copy = length < cap - 1 ? length : cap - 1;
      if (copy < 0) copy = 0;
      std::memcpy(name_buf, it->first.data(), static_cast<size_t>(copy));
      name_buf[copy] = 0;
    }
    *out_index = it->second;
    return length;
  } catch (...) {
    return -1;
  }
}

// Replaces matches of the pattern in `text` (UTF-8, `text_len` bytes) with
// `rewrite`. When `global` is nonzero every non-overlapping match is replaced;
// otherwise only the first. `rewrite` may reference capture groups with
// \1..\9, exactly as RE2's own Replace/GlobalReplace do. Returns a freshly
// allocated buffer of the result (release with re2_free_string), writes its
// byte length to *out_len and the number of replacements to *out_count.
// Returns null on failure (null handle, uncompiled pattern, or allocation).
RE2_EXPORT char* re2_replace(void* handle, const char* text, int32_t text_len,
                             const char* rewrite, int32_t rewrite_len,
                             int32_t global, int32_t* out_len,
                             int32_t* out_count) {
  if (handle == nullptr || out_len == nullptr || out_count == nullptr) {
    return nullptr;
  }
  try {
    RE2* re = static_cast<RE2*>(handle);
    if (!re->ok()) return nullptr;
    std::string str(text, static_cast<size_t>(text_len));
    const StringPiece rw(rewrite, static_cast<size_t>(rewrite_len));
    const int count = global != 0 ? RE2::GlobalReplace(&str, *re, rw)
                                  : (RE2::Replace(&str, *re, rw) ? 1 : 0);
    // Allocate at least one byte so success always returns non-null, even when
    // the whole input was replaced with nothing.
    char* out = static_cast<char*>(std::malloc(str.empty() ? 1 : str.size()));
    if (out == nullptr) return nullptr;
    if (!str.empty()) std::memcpy(out, str.data(), str.size());
    *out_len = static_cast<int32_t>(str.size());
    *out_count = count;
    return out;
  } catch (...) {
    return nullptr;
  }
}

// Releases a buffer returned by re2_replace. Safe on a null pointer.
RE2_EXPORT void re2_free_string(char* p) { std::free(p); }

// Releases a handle from re2_compile. Safe on a null handle.
RE2_EXPORT void re2_free(void* handle) { delete static_cast<RE2*>(handle); }

// --- RE2::Set: match many patterns against one input in a single pass. -------
//
// A Set compiles N patterns into one automaton and, in one linear scan, reports
// which of them matched. This is what a backtracking engine cannot do: with the
// builtin, testing N rules means N separate passes, each able to blow up.

// Creates an empty, unanchored Set with default options. Never null unless
// allocation fails.
RE2_EXPORT void* re2_set_new(int32_t case_sensitive, int32_t dot_all) {
  try {
    RE2::Options options;
    options.set_log_errors(false);
    if (case_sensitive == 0) options.set_case_sensitive(false);
    if (dot_all != 0) options.set_dot_nl(true);
    return static_cast<void*>(
        new (std::nothrow) RE2::Set(options, RE2::UNANCHORED));
  } catch (...) {
    return nullptr;
  }
}

// Adds a pattern and returns its index (0-based, in add order), or -1 if the
// pattern is invalid. On -1, up to `err_cap` bytes of RE2's diagnostic are
// written into `err` (also NUL-terminated for convenience, but that byte can
// legitimately appear before the end of the message -- the diagnostic can
// quote a slice of the original pattern, and this shim accepts patterns with
// embedded NULs), and the number of bytes actually written is stored in
// `*err_len`, so the caller can read exactly that many bytes instead of
// scanning for a terminator. Adding is only valid before compile.
RE2_EXPORT int32_t re2_set_add(void* handle, const char* pattern,
                               int32_t pattern_len, char* err,
                               int32_t err_cap, int32_t* err_len) {
  if (handle == nullptr) return -1;
  try {
    std::string error;
    const int index = static_cast<RE2::Set*>(handle)->Add(
        StringPiece(pattern, static_cast<size_t>(pattern_len)), &error);
    if (index < 0 && err != nullptr && err_cap > 0) {
      const int32_t n = static_cast<int32_t>(error.size()) < err_cap - 1
                            ? static_cast<int32_t>(error.size())
                            : err_cap - 1;
      if (n > 0) std::memcpy(err, error.data(), static_cast<size_t>(n));
      err[n] = '\0';
      if (err_len != nullptr) *err_len = n;
    }
    return index;
  } catch (...) {
    return -1;
  }
}

// Compiles the added patterns into the automaton. 1 on success, 0 if it could
// not compile (for example the combined program exceeded the memory budget).
// Must be called once, after all Add calls and before any Match.
RE2_EXPORT int32_t re2_set_compile(void* handle) {
  if (handle == nullptr) return 0;
  try {
    return static_cast<RE2::Set*>(handle)->Compile() ? 1 : 0;
  } catch (...) {
    return 0;
  }
}

// Matches `text` against the compiled Set, writing the indices that matched (in
// ascending order) into `out` (up to `out_cap` entries). Returns the total
// number of matches; if that exceeds `out_cap` the caller retries with a bigger
// buffer. Returns -1 on error (including matching before compile).
RE2_EXPORT int32_t re2_set_match(void* handle, const char* text,
                                 int32_t text_len, int32_t* out,
                                 int32_t out_cap) {
  if (handle == nullptr) return -1;
  try {
    std::vector<int> matched;
    if (!static_cast<RE2::Set*>(handle)->Match(
            StringPiece(text, static_cast<size_t>(text_len)), &matched)) {
      return 0;  // no matches
    }
    const int32_t total = static_cast<int32_t>(matched.size());
    if (out != nullptr) {
      const int32_t n = total < out_cap ? total : out_cap;
      for (int32_t i = 0; i < n; i++) out[i] = matched[i];
    }
    return total;
  } catch (...) {
    return -1;
  }
}

// Releases a handle from re2_set_new. Safe on a null handle.
RE2_EXPORT void re2_set_free(void* handle) {
  delete static_cast<RE2::Set*>(handle);
}

}  // extern "C"
