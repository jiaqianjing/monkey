# 中文输入质量评测

此评测衡量 Monkey 本地拼音引擎在固定输入上的候选排序、完整输出和按键处理耗时。它没有使用微信或搜狗的实测数据，因此不能用于声称追平或超过这些产品。

## 固定语料

语料位于 [`input-quality-v1.json`](../Tests/MonkeyPinyinTests/Fixtures/input-quality-v1.json)，版本为 1，共 110 条。预期在第一次运行基线前确定；后续不能因为当前结果不好而删除条目、降低要求或增加命中结果。确需修正语料时应提升版本，并对两种配置重新测量。

| 类别 | 数量 | 评分层级 |
| --- | ---: | --- |
| 常用词全拼 | 20 | 引擎排序 |
| 日常短语 | 16 | 引擎排序 |
| 完整句子 | 12 | 引擎排序 |
| 简拼 | 10 | 引擎排序 |
| 拼音错拼 | 12 | 引擎排序 |
| 专业术语 | 15 | 引擎排序 |
| 中文标点 | 4 | 引擎自动输出 |
| 数字、版本与 IP | 6 | 前端场景的引擎探针 |
| 网址与邮箱 | 6 | 前端场景的引擎探针 |
| 英文、中英文字面混输 | 6 | 前端场景的引擎探针 |
| 中文与数字、英文混合 | 3 | 前端场景的引擎探针 |

每项具有 `category`、`input`、`expected`、`expectation`，并通过 `layer` 标识引擎排序项或前端场景。`expected` 可包含多个明确列出的合理答案，例如没有上下文的 `sj` 可指“时间”“手机”“世界”。这些少量歧义项不代表唯一意图识别能力。

错拼包含相邻字母交换、漏键、重复键和拼写混淆。其中 `pignyin → 拼音` 是额外字母/`in`、`ing` 混淆的挑战，不应误读成纯相邻交换。错拼预期是产品目标，不是宣称当前方案已经支持所有纠错。

## 运行

```sh
swift build -c release --product MonkeyBenchmark
.build/release/MonkeyBenchmark \
  --data-dir Resources/Rime \
  --library Vendor/Rime/lib/librime.1.dylib \
  --output-json .build/input-quality-current.json \
  --label current \
  --quiet
```

可用 `--corpus` 指定其他版本的 JSON；`--quiet` 仅关闭逐项控制台行，JSON 仍包含所有输入、候选、原文、提交结果和每键观测。省略 `--quiet` 可在终端看到各项结果。

工具为每次运行创建独立临时用户目录，结束后删除；每项使用独立会话。排序项不主动选中候选，前端探针最后运行，避免探针中的数字选词、空格提交影响之前的排名。它不会读取用户的真实学习词库。

比较两个输入配置时，使用同一个 release 可执行文件和同一份固定语料，分别指定两个 `--data-dir`。只在实际观测后记录结果，不把质量不佳的情况包装成测试通过。测量结果不匹配预期不会令进程失败；参数、文件或引擎初始化错误会返回非零状态。它是诊断工具，不代替现有 XCTest 或实际输入验收。

## 指标含义

- **Top 1**：首个完整输出与 `expected` 中某一项完全相同。
- **Top 5**：前五个完整输出中至少有一项完全相同。当前引擎每页提供七项，本工具只按前五项计分，不翻页寻找答案。
- **完整输出**：测试宿主已收到的引擎提交/未处理键原样输出，加上当前候选。没有组合文本且已自动提交的标点作为一个输出参与评分。
- **要求满足率**：`expectation=top1` 的条目要求首选命中，`top5` 的条目要求前五命中。它与无差别 Top 1 比例是不同指标。
- **候选长度**：记录每个候选的 Swift `String.count`，即扩展字素簇数量，同时记录完整输出长度。不是词库唯一词条数，也不是只按 UTF-16 长度计数。
- **按键耗时**：分别计时 `session.process` 与包含提交读取、候选快照的整个更新步骤，报告中位数、P95、P99、最大值。单位为微秒，不包含实际键盘、宿主应用、窗口绘制或屏幕显示延迟。

比较采用区分大小写的精确匹配，不自动移除空格或纠正标点来制造命中。每个结果保留候选、候选注释、原始输入、未处理键、实际提交和预编辑文本，便于解释失败。

### 前端场景的边界

数字、网址、邮箱和英文混输需要应用前端决定何时保留英文、何时提交中文、何时将键交给引擎。因此 21 个 `layer=frontend` 场景不进入 89 项引擎排名分母；引擎探针失败不能直接叫作应用输入失败。

18 项 `preserve` 探针分别报告：未额外操作时的完整原样输出，以及显式发送原文 Return 后的实际输出。工具只计算真实提交和未处理键的输出，不用原始 `input` 拼接一个虚假的成功结果。Return 后命中也不等于无需用户操作的自动保留。

另外三个中文混合场景仅记录引擎候选，仍需要前端测试证明最终应用行为。

### 生产组合输入路径

`--composition` 仅运行 21 个 `layer=frontend` 条目，逐键经过应用实际使用的 `CompositionSession` 和真实 Rime。自动识别英文、英文空格选项固定开启，不读取真实用户偏好；每项仍创建独立原生会话。它覆盖组合输入路由，未包含 InputMethodKit、系统事件送达或候选窗口。

```sh
.build/release/MonkeyBenchmark --composition \
  --data-dir Resources/Rime \
  --library Vendor/Rime/lib/librime.1.dylib \
  --output-json .build/input-quality-composition.json \
  --label production-composition \
  --quiet
```

此模式保留同一 JSON 结构，同时用 `mode`、`comparisonBoundary`、逐项 `evaluationScope` 和 `compositionSourceSHA256` 明确层级。18 项字面场景在记录当前输出后，再发送原文 Return 并比较实际结果；尚在组合区、尚未提交的文字不等于已经丢失。三个中文连写混合场景仍是参考项，不计为排序或应用验收通过。

报告的 `harnessBinarySHA256` 是实际执行文件的哈希。做配置对比应使用同一个新构建的 runner，确保二进制哈希一致；源码哈希只是运行时文件的读数，不应单独当作已编译代码的身份凭据。

## 基线观测

基线数据来自 `76db9e6553b626a80c5af0735bfcdbe53d0d6b9c` 的配置和词库 Git 快照，保存在 `.build/quality-baseline/Resources/Rime`。报告位于 [`baseline-76db9e6.json`](../Tests/MonkeyPinyinTests/Fixtures/baseline-76db9e6.json)。

“76db9e6 基线”指输入数据快照；基准工具及当前桥接观测字段是本轮新增内容，并非声称原提交已经包含它们。报告明确记录运行时 Git HEAD、工作区是否有修改，以及语料、工具、引擎、桥接代码、配置、运行库与部署词典的 SHA-256。后续比较应检查这些字段，确认比较边界。

2026-10-29 在当前 Apple Silicon Mac 上以 release 模式实测：

| 引擎类别 | 数量 | Top 1 | Top 5 |
| --- | ---: | ---: | ---: |
| 常用词全拼 | 20 | 20 | 20 |
| 日常短语 | 16 | 16 | 16 |
| 完整句子 | 12 | 10 | 10 |
| 简拼 | 10 | 6 | 8 |
| 错拼 | 12 | 4 | 6 |
| 专业术语 | 15 | 13 | 14 |
| 中文标点 | 4 | 4 | 4 |
| **合计** | **89** | **73（82.0%）** | **78（87.6%）** |

按每项指定的 Top 1/Top 5 要求，满足 78/89 项。首候选平均长度约 3.59 个字素，包含已提交前缀后的首输出平均长度约 3.47 个字素；长度本身不是质量分数。

按键处理 P95 为 972.67 µs，含提交与快照读取的更新步骤 P95 为 989.67 µs。进程初始化约 2057 ms；该基线目录没有 Git 忽略的预编译词典，因此不能把此初始化数值与已经包含 `build/` 的新配置直接相减，宣称冷启动加速。正式性能对比应统一预编译资源状态并重复测量。

18 项字面保留探针中，自动原样输出为 5/18，显式原文 Return 后为 9/18。该结果说明引擎探针与完整混输前端之间有边界，不能作为整体应用的混输得分。

基线暴露的具体问题包括“明天下午亮点开会”与预期“两点”的排序、部分简拼前五没有目标词、部分错拼未恢复，以及专业语境“异步”排名较后。`在/再` 等同音选择也受上下文影响；此语料给定目标表达的失败应保留，不意味着其他同音写法在所有语境都错误。

这套语料仍有限：没有真实用户输入日志、长期个性化、方言、姓名覆盖率或微信/搜狗同条件对照。实际可用性还需实体键盘、不同宿主应用和日常使用验证。

## 额外精确拼音回归样本

[`exact-pinyin-holdout-v1.json`](../Tests/MonkeyPinyinTests/Fixtures/exact-pinyin-holdout-v1.json) 含另 150 个不与主语料输入重复的精确全拼。文件名保留 `holdout`，其作用是检查常用精确输入的退化，不是独立外部验证集，也不代表真实用户意图的准确率。

样本从固定雾凇版本 `da1fbe602e38f26db846fa10120ee64c2b0324c0` 的 `cn_dicts/base.dict.yaml` 生成，源文件 SHA-256 为 `0418d5103d8e40c8fff4b686a873ad03e9836cd0419ecae0b7e1e2526312dba0`。保留 2～4 个 BMP 汉字、去掉拼音空格后仅含 `a-z`、词频至少 500000 的条目，排除主语料所有输入；用 Python `random.Random(20261029).shuffle(rows)` 打乱，按拼音码去重后取前 150 项。预期在运行前写入 JSON，不按观测结果更改。

这仍是同一词库内部采样，且同音词可能有多种合理表达。应比较相同固定样本的前后变化，不能把其较高命中率当作整体产品质量。

## 0.2.0 最终对照

首次基线文件保持不变。为避免工具源码变化影响对照，最终使用同一个新编译的 release runner，顺序重跑旧数据、新数据、150 项精确拼音前后及生产组合路径。五份报告的 `harnessBinarySHA256` 均为 `1c12d6581817bab9a65d4fe31a45695dfd92d5bcb114c69e56cbbe0e3d26abae`，工具、引擎、桥接代码和运行库哈希也一致。实际执行文件与运行时源码读数分别记录，不混为一项。

| 主语料的引擎指标 | 旧数据重跑 | 0.2.0 数据 |
| --- | ---: | ---: |
| Top 1 | 73/89（82.0%） | 83/89（93.3%） |
| Top 5 | 78/89（87.6%） | 84/89（94.4%） |
| 错拼 Top 1 | 4/12 | 12/12 |
| 错拼 Top 5 | 6/12 | 12/12 |
| 按键处理 P95 | 1.221 ms | 7.970 ms |
| 按键处理 P99 | 2.325 ms | 18.005 ms |
| 按键处理最大值 | 7.305 ms | 25.324 ms |

常用词、日常短语和中文标点仍全部命中，主语料未出现原先 Top 1 或 Top 5 命中变为不命中的情况。首候选平均长度从约 3.59 变为 3.51 个字素；长度不是质量分数。

纠错收益伴随明确的按键尾延迟增加，不能只报告命中率改善。以上是固定语料、单次本机观测，仍需重复性能测量及实际连续输入验证。初始化资源状态不同，旧快照没有预编译 `build/`、新数据包含预编译文件，因此初始化时间不用于证明本轮排序优化加速。

额外 150 项精确拼音样本前后均为 Top 1 144/150、Top 5 150/150，逐项首选输出及目标排名没有变化。仍不能据此推广到全部中文输入。

生产 `--composition` 路径在明确发送原文 Return 后，18/18 个字面场景精确保留，包括带 `+tag` 的邮箱、`macOS 13`、`Python 3.12` 和 `API v2`。未确认时文字仍在组合区，所以“已自动上屏”为 0/18；这不是文字丢失，也不应与原始引擎的未处理键直接上屏数比较。

三个无显式选词边界的中文连写混合场景仍未命中，不计为通过：

- `wozaiyongmacOS`：仍出现“我再用马车”等候选。
- `qingfasongPDFwenjian`：当前只得到“请发送”等分段候选。
- `mingtian10diankaihui`：仍出现“明天0点开会”，数字在尚未确认中文时参与了候选选择。

当前使用这些场景时需要先确认中文候选，再继续输入英文或数字；不能宣称已支持任意连写内容的自动拆分。生产组合路径观测仍不包含 IMK、系统按键送达和候选窗口，实体键盘及跨应用验收不可由本报告替代。

最终报告：

- [旧数据统一 runner 重跑](../Tests/MonkeyPinyinTests/Fixtures/baseline-0.1.0-rerun.json)
- [0.2.0 引擎对照](../Tests/MonkeyPinyinTests/Fixtures/after-0.2.0.json)
- [150 项旧数据](../Tests/MonkeyPinyinTests/Fixtures/holdout-baseline-76db9e6.json)
- [150 项 0.2.0 数据](../Tests/MonkeyPinyinTests/Fixtures/holdout-after-0.2.0.json)
- [0.2.0 生产组合输入](../Tests/MonkeyPinyinTests/Fixtures/composition-0.2.0.json)

重现最终对照时，先将旧版本 `Resources/Rime` 保存为独立目录，再使用同一 runner 连续运行；不要在两次测量之间重编工具、改词库或改预期。例如旧数据已位于 `.build/quality-baseline/Resources/Rime` 时：

```sh
swift build -c release --product MonkeyBenchmark
runner=.build/release/MonkeyBenchmark
"$runner" --data-dir .build/quality-baseline/Resources/Rime --output-json .build/before.json --quiet
"$runner" --data-dir Resources/Rime --output-json .build/after.json --quiet
"$runner" --corpus Tests/MonkeyPinyinTests/Fixtures/exact-pinyin-holdout-v1.json --data-dir .build/quality-baseline/Resources/Rime --output-json .build/exact-before.json --quiet
"$runner" --corpus Tests/MonkeyPinyinTests/Fixtures/exact-pinyin-holdout-v1.json --data-dir Resources/Rime --output-json .build/exact-after.json --quiet
"$runner" --composition --data-dir Resources/Rime --output-json .build/composition.json --quiet
```
