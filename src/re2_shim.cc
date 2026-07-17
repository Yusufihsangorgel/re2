// C ABI shim over the vendored RE2 engine. RE2 matches on UTF-8 bytes and
// returns byte offsets; the Dart side works in that byte space and converts
// back to UTF-16 string indices. Every entry point is `extern "C"` and takes
// explicit lengths (never NUL-terminated), so embedded NULs and binary text
// pass through unharmed. No C++ exception is allowed to cross the boundary:
// each function catches everything and reports failure through its return
// value, exactly as the blake3_ffi and simdjson_dart shims do.

#include <cstdint>
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
                             int32_t dot_all) {
  try {
    RE2::Options options;
    options.set_log_errors(false);
    if (case_sensitive == 0) options.set_case_sensitive(false);
    if (dot_all != 0) options.set_dot_nl(true);

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

// 1 if the pattern compiled cleanly, 0 otherwise (including a null handle).
RE2_EXPORT int32_t re2_ok(void* handle) {
  if (handle == nullptr) return 0;
  return static_cast<RE2*>(handle)->ok() ? 1 : 0;
}

// The compile error message as a NUL-terminated string, valid until the
// handle is freed. Returns a static string when the handle is null.
RE2_EXPORT const char* re2_error(void* handle) {
  if (handle == nullptr) return "out of memory";
  return static_cast<RE2*>(handle)->error().c_str();
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

// Releases a handle from re2_compile. Safe on a null handle.
RE2_EXPORT void re2_free(void* handle) { delete static_cast<RE2*>(handle); }

}  // extern "C"
