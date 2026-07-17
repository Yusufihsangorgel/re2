import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the RE2 shim and the vendored RE2 engine (release 2022-06-01,
/// the last version before RE2 took a hard dependency on Abseil) into a
/// dynamic library at build time.
///
/// The 22 RE2 translation units are the exact set RE2's own CMakeLists.txt
/// builds into `libre2`; nothing is generated at build time. The include
/// root is the vendored tree so RE2's `#include "re2/..."` and
/// `#include "util/..."` paths resolve, and the shim's `re2/re2.h` include
/// resolves the same way.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final targetOS = input.config.code.targetOS;

    const re2Sources = <String>[
      'src/third_party/re2/re2/bitstate.cc',
      'src/third_party/re2/re2/compile.cc',
      'src/third_party/re2/re2/dfa.cc',
      'src/third_party/re2/re2/filtered_re2.cc',
      'src/third_party/re2/re2/mimics_pcre.cc',
      'src/third_party/re2/re2/nfa.cc',
      'src/third_party/re2/re2/onepass.cc',
      'src/third_party/re2/re2/parse.cc',
      'src/third_party/re2/re2/perl_groups.cc',
      'src/third_party/re2/re2/prefilter.cc',
      'src/third_party/re2/re2/prefilter_tree.cc',
      'src/third_party/re2/re2/prog.cc',
      'src/third_party/re2/re2/re2.cc',
      'src/third_party/re2/re2/regexp.cc',
      'src/third_party/re2/re2/set.cc',
      'src/third_party/re2/re2/simplify.cc',
      'src/third_party/re2/re2/stringpiece.cc',
      'src/third_party/re2/re2/tostring.cc',
      'src/third_party/re2/re2/unicode_casefold.cc',
      'src/third_party/re2/re2/unicode_groups.cc',
      'src/third_party/re2/util/rune.cc',
      'src/third_party/re2/util/strutil.cc',
    ];

    final builder = CBuilder.library(
      name: 're2_shim',
      assetName: 'src/bindings.dart',
      sources: ['src/re2_shim.cc', ...re2Sources],
      includes: ['src/third_party/re2'],
      // RE2's threading wrappers use std::mutex/std::once. On Linux that
      // needs libpthread; -pthread also sets the right defines. It is a
      // no-op that MSVC never sees (Windows uses its own primitives), and
      // Apple libc++ links the pthread symbols unconditionally.
      flags: [if (targetOS == OS.linux) '-pthread'],
      language: Language.cpp,
      // Translated per compiler (-std= vs /std:); a raw flag would be
      // silently ignored by MSVC.
      std: 'c++14',
    );
    await builder.run(input: input, output: output);
  });
}
