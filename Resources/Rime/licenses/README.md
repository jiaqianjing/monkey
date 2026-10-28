# Dictionary attribution

Monkey bundles the unmodified `cn_dicts/8105.dict.yaml`, `base.dict.yaml` and
`ext.dict.yaml` files from [Rime Ice](https://github.com/iDvel/rime-ice), revision
`da1fbe602e38f26db846fa10120ee64c2b0324c0` (retrieved 2026-10-29).
The upstream project distributes them under GPL-3.0; the complete license is
included in `rime-ice-GPL-3.0.txt`. Original comments, source acknowledgements,
word frequencies and pronunciation annotations are retained in each file.

`DICTIONARY-SOURCES.json` records each exact upstream URL, size and SHA-256.
The three files contain approximately 900,000 data rows, including alternate
pronunciations; this is not a count of unique words or a quality benchmark.
Their content includes names and specialist vocabulary as well as everyday
phrases. Candidate quality remains subject to real typing evaluation.

The surrounding `default.yaml`, `monkey_pinyin.schema.yaml` and
`monkey_pinyin.dict.yaml` are Monkey's own configuration. We do not bundle the
Squirrel frontend or the Rime Ice Lua plugins. The dictionary manifest imports
only the three files above. User learning writes to the user's Rime directory,
never to the bundled dictionary files.

The librime binary and its separate dependency notices are prepared by
`scripts/bootstrap-rime.sh` in `Vendor/Rime/`. The release packager copies those
notices into the application's resources.
