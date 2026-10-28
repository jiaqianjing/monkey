# Dictionary attribution

Monkey bundles the unmodified `cn_dicts/8105.dict.yaml`, `base.dict.yaml` and
`ext.dict.yaml` files from [Rime Ice](https://github.com/iDvel/rime-ice), revision
`da1fbe602e38f26db846fa10120ee64c2b0324c0` (retrieved 2026-10-29).
The upstream project distributes them under GPL-3.0; the complete license is
included in `rime-ice-GPL-3.0.txt`. Original comments, source acknowledgements,
word frequencies and pronunciation annotations are retained in each file.

`DICTIONARY-SOURCES.json` records each exact upstream URL, size and SHA-256.
The three Chinese files contain approximately 900,000 data rows, including alternate
pronunciations; this is not a count of unique words or a quality benchmark.
Their content includes names and specialist vocabulary as well as everyday
phrases. Candidate quality remains subject to real typing evaluation.

The unmodified English sources `en.dict.yaml`, `en_ext.dict.yaml` and `cn_en.txt`
from that same pinned Rime Ice revision are preserved in `cn_dicts/upstream/`,
including their original source acknowledgements. `scripts/bootstrap-rime.sh`
verifies their SHA-256 and generates `cn_dicts/monkey_english_terms.dict.yaml`.
The derived list lowercases alphabetic lookup codes, excludes lookup codes
shorter than three letters, and removes duplicate text/code pairs. Its roughly
23,700 entries cover English words, product names and Chinese/English mixed
phrases such as `U盘` and `T恤`. GPL-3.0 also applies to this derived list; the
modification and provenance are recorded in its header and the JSON manifest.

`cn_dicts/monkey_common.dict.yaml` is Monkey's own small, editable supplement of
117 everyday conversation and work phrases. It is distributed under the
project's MIT license. Its weights are editorial priors, not measured usage
counts. They improve a general corpus's coverage of greetings and short
messages through Rime's usual frequency sorting; they do not pin candidate
positions or bypass personal learning.

The surrounding YAML schemas/manifests are Monkey's own configuration. We do
not bundle the Squirrel frontend or the Rime Ice Lua plugins. The main Chinese
dictionary imports the three upstream Chinese files and the small conversation
supplement. English uses a separate table translator without user learning or
automatic sentence construction. User learning for Chinese writes to the
user's Rime directory, never to the bundled dictionary files.

Keyboard-error spellings use Rime's `fuzz` operation, which carries a lower
credibility than exact spelling; initial-only shortcuts use `abbrev`. They do
not enable n/l or z/zh pronunciation merging. `derive/.../.../correction` was
evaluated and excluded because this librime version can put automatically
constructed phrases ahead of intended corrections. See the upstream
[spelling algebra guide](https://github.com/rime/home/wiki/SpellingAlgebra)
and [librime 1.17 calculus implementation](https://github.com/rime/librime/blob/33e7814/src/rime/algo/calculus.cc).

The librime binary and its separate dependency notices are prepared by
`scripts/bootstrap-rime.sh` in `Vendor/Rime/`. The release packager copies those
notices into the application's resources.
