# Third-party notices

The MIT license at the repository root applies to Monkey's original source code.
Third-party libraries, schemas, dictionaries and data keep their own licenses;
the MIT license does not relicense them.

## Rime runtime

Monkey loads [librime](https://github.com/rime/librime), licensed under BSD-3-Clause.
`scripts/bootstrap-rime.sh` downloads a pinned official macOS universal release
and verifies its SHA-256. Its core library statically includes its third-party
dependencies and links only to macOS system libraries. The exact runtime version
and bundled license texts are recorded in `Vendor/Rime/BUILD-MANIFEST.txt` and
`Vendor/Rime/licenses/` after bootstrapping. Those files are copied into the app
at `Contents/Resources/Licenses/` during packaging. Binaries are build artifacts
and are not committed to this repository.

The upstream runtime incorporates dependencies such as Boost and utf8cpp
(BSL-1.0), glog, LevelDB and darts-clone (BSD-3-Clause), OpenCC (Apache-2.0),
marisa-trie (BSD-2-Clause / LGPL-2.1 dual license), yaml-cpp (MIT) and RapidJSON
(MIT, including its component notices). The generated manifest and included upstream license texts are the
authoritative inventory for each binary build. See the runtime's upstream
third-party notices for its full static dependency list.

The copied Rime C API header in `Sources/CRimeBridge/include/rime_api.h` also
retains its upstream BSD-3-Clause license; its complete license text is included
at [docs/licenses/librime-BSD-3-Clause.txt](docs/licenses/librime-BSD-3-Clause.txt).

## Chinese schemas and dictionaries

The initial Chinese data is derived from
[rime-ice](https://github.com/iDvel/rime-ice), distributed under GPL-3.0.
The original license, component notices and pinned upstream revision are retained
under `Resources/Rime/licenses/`. The data remains under its original terms.
See those notices for the component dictionary sources and their licenses.

Monkey is a new InputMethodKit frontend. It does not incorporate Squirrel's
GPL-licensed frontend implementation. Apple's InputMethodKit APIs and Squirrel's
published bundle metadata were consulted as documentation of the macOS input
method format.

## Apple platform frameworks and OpenAI services

AppKit, Carbon, Foundation, InputMethodKit, Security and SwiftUI are supplied by
macOS and are not redistributed as third-party source. ChatGPT authentication
and inference use OpenAI's documented service interfaces; OpenAI trademarks and
service terms are separate from this repository's software license.
