<p align="center">
  <img src="Resources/AppIcon.png" alt="Monkey 盲 key：青柠色键帽与输入光标" width="104" height="104">
</p>

<h1 align="center">Monkey · 盲 key</h1>

<p align="center">
  <strong>中文输入自如，英文表达随手。</strong><br>
  为 macOS 打造的开源拼音输入法：本地选词、日常混输，在输入框里预览英文。
</p>

<p align="center">
  <a href="https://github.com/jiaqianjing/monkey/releases/tag/v0.2.3"><img src="https://img.shields.io/badge/release-v0.2.3-D7F879?style=flat-square&amp;labelColor=171B2E&amp;color=D7F879" alt="v0.2.3"></a>
  <img src="https://img.shields.io/badge/Apple-notarized-171B2E?style=flat-square" alt="Developer ID 签名、Apple 公证并附带公证票据">
  <img src="https://img.shields.io/badge/macOS-13%2B-171B2E?style=flat-square" alt="最低系统要求 macOS 13">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-171B2E?style=flat-square" alt="Apple Silicon arm64">
  <a href="https://github.com/jiaqianjing/monkey/actions/workflows/ci.yml"><img src="https://github.com/jiaqianjing/monkey/actions/workflows/ci.yml/badge.svg" alt="Build and test macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-171B2E?style=flat-square" alt="原创代码 MIT 许可证"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/jiaqianjing/monkey/releases/download/v0.2.3/Monkey-0.2.3-macos-arm64-notarized.zip">下载 macOS 版 ↗</a></strong>
  &nbsp; · &nbsp; <a href="docs/install.md">安装指南</a>
  &nbsp; · &nbsp; <a href="https://github.com/jiaqianjing/monkey/releases/tag/v0.2.3">更新记录</a>
  &nbsp; · &nbsp; <a href="https://github.com/jiaqianjing/monkey/issues/new">反馈问题</a>
  &nbsp; · &nbsp; <a href="#support">请我喝杯咖啡 ☕</a>
</p>

<p align="center">
  <img src="docs/assets/readme-hero.svg" alt="Monkey 的本地中文输入与中译英确认流程示意" width="100%">
  <br><sub>输入流程示意，非应用截图。翻译由你开启，英文由你确认。</sub>
</p>

<p align="center">
  <a href="#download">下载与安装</a> · <a href="#translation">中译英</a> · <a href="#shortcuts">快捷键</a> · <a href="#quality">输入质量</a> · <a href="#development">从源码构建</a>
</p>

---

## 中文输入优先，翻译随手可用

| | Monkey 能做什么 |
| :--- | :--- |
| **熟悉的中文输入** | 基于 librime 与雾凇拼音词库，支持全拼、简拼、整句候选和本机用户词学习。补充日常表达词频，让“你好”“谢谢”“好的”等常用词更容易选中。 |
| **照顾真实打字习惯** | 常见换位、漏键、重复键纠错；英文与中英词候选；保留网址、邮箱、小数和版本号的 ASCII 符号。横排、竖排和英文空格习惯均可调整。 |
| **在输入框里写英文** | 用中文组织表达，查看英文预览，再亲自确认上屏。通过官方 Sign in with ChatGPT 连接符合条件的订阅账号，无需填写 API key。 |

普通拼音输入、候选排序和用户词学习在本地完成，无需登录。只有你开启翻译模式后，当前中文草稿才会发送到 OpenAI。

## 看看实际界面

截图拍摄于 Monkey 0.2.1，展示原生设置与翻译试写窗口。点击图片可放大。截图中为一次实际试译，具体表达和耗时随模型、网络而变化；输入法的实体键盘与跨应用验证另见 [验收记录](docs/validation.md)。

<table>
  <tr>
    <td align="center" width="50%"><a href="docs/assets/settings-overview.png"><img src="docs/assets/settings-overview.png" alt="Monkey 设置概览：中文输入、中译英入口与三步引导" width="100%"></a><br><sub>概览 · 输入与翻译入口</sub></td>
    <td align="center" width="50%"><a href="docs/assets/settings-translation.png"><img src="docs/assets/settings-translation.png" alt="Monkey 中译英试写：中文草稿、表达语气与一次完成的英文译文" width="100%"></a><br><sub>中译英 · 先在这里试写一句</sub></td>
  </tr>
</table>

## 试试这些输入

| 场景 | 输入 | 结果或操作 |
| :--- | :--- | :--- |
| 日常简拼 | `nh` / `xx` / `hd` | 首选“你好” / “谢谢” / “好的” |
| 常见错拼 | `nihoa` | 首选“你好” |
| 中英词 | `upan` / `txu` | 候选“U盘” / “T恤” |
| 英文与版本 | `macOS 13` / `Python 3.12` | 保留大小写、空格与小数点 |
| 邮箱与网址 | `first.last+tag@example.co.uk` / `https://github.com` | 保留 ASCII 符号，按 `Return` 原样确认 |

混合输入时，先确认中文候选，再继续输入英文或数字。例如，先输入并确认“我在用”，再输入 `macOS`。目前尚未支持把任意无分隔长串自动拆成正确的中英文句子。候选会随个人学习发生变化。

<a id="translation"></a>

### 用中文写，确认英文上屏

1. 点击候选条里的 **中译英**，或按 `Control + Shift + T` 开启。
2. 正常用拼音选词，组成中文草稿，等待英文预览完成。
3. 按 `Control + Return` 将英文上屏；直接按 `Return` 使用中文原文（`Shift + Return` 也可）。

```text
中文草稿   明天下午我有空，我们把会议改到三点吧。
英文预览   I’m free tomorrow afternoon. Let’s move the meeting to 3:00 p.m.
确认上屏   Control + Return
```

上方是一次实际翻译示例，具体表达会因模型和上下文而变化。英文经确认才会写入当前输入框；请求失败时保留中文草稿。修改草稿后，需等待新版本翻译完成。

<a id="download"></a>

## 下载与安装

**当前版本：[0.2.3](https://github.com/jiaqianjing/monkey/releases/tag/v0.2.3)** · Apple Silicon（arm64）· 最低要求 macOS 13.0

安装器与输入法均使用 Developer ID 签名，通过 Apple 公证并附带公证票据（stapled）。新版通过原生安装器安装，无需在系统安全设置中手动添加打开例外；macOS 仍可能显示正常的首次下载确认。

1. [下载 ZIP](https://github.com/jiaqianjing/monkey/releases/download/v0.2.3/Monkey-0.2.3-macos-arm64-notarized.zip) 并解压，双击 **`Monkey Installer.app`**。
2. 在安装器中点击 **安装**。完成后，从 macOS 菜单栏输入法菜单手动选择 **Monkey 拼音**。
3. 若没有出现，在 **系统设置 → 键盘 → 文字输入 → 编辑** 中添加；首次安装或更新后仍无法使用时，注销当前 macOS 用户再登录。
4. 如需翻译，点击安装器里的 **打开 Monkey 设置**，选择 **Continue with ChatGPT**，在浏览器完成登录与授权。

安装位置为 `~/Library/Input Methods/Monkey.app`，不需要 `sudo`。更新前先完成当前输入并退出 Monkey 设置，再运行新版安装器；用户词库、偏好与账号连接会保留。从旧版临时签名迁移后，系统仍可能要求重新确认 Monkey 的钥匙串访问。

暂不提供 Intel 安装包。输入体验仍在持续打磨；签名、公证和当前 Mac 上的检查不代表所有支持系统、另一台 Mac 或全部宿主应用均已验收。若需回退，可下载 [0.2.1 开发预览](https://github.com/jiaqianjing/monkey/releases/tag/v0.2.1)；它未经过公证，详见[旧版安装与回退说明](docs/install.md#legacy-preview)。

[详细安装与卸载说明](docs/install.md) · [SHA-256 校验文件](https://github.com/jiaqianjing/monkey/releases/download/v0.2.3/Monkey-0.2.3-macos-arm64-notarized.sha256)

<details>
<summary>打开设置 / 校验下载文件</summary>

打开设置：

```sh
open -a "$HOME/Library/Input Methods/Monkey.app" --args --settings
```

将 ZIP 与 `.sha256` 文件下载到同一目录后，在该目录运行：

```sh
shasum -a 256 -c Monkey-0.2.3-macos-arm64-notarized.sha256
```

</details>

<a id="shortcuts"></a>

## 常用快捷键

| 操作 | 快捷键 |
| :--- | :--- |
| 选首个候选 / 按编号选词 | `Space` / 数字键 |
| 普通模式：原样确认拼音或英文；翻译模式：提交中文草稿 | `Return` |
| 候选翻页 | `Page Up` / `Page Down` 或 `-` / `=` |
| 切换中文拼音 / 英文直输 | `Shift + Space` |
| 开关中译英模式 | `Control + Shift + T` |
| 确认英文 / 使用中文原文 | `Control + Return` / `Return`（或 `Shift + Return`） |
| 清除拼音 / 取消翻译请求并保留草稿 | `Esc` |

右键中文候选可尝试清除该候选的个人学习记录，内置词库仍保留。候选条顶部可直接开启中译英或点击齿轮进入设置。悬浮窗只在拼音输入或未确认草稿存在时显示，提交、取消或切走后收起。在设置的「中文输入」中，可调整英文自动识别、候选布局，以及选中英文词后是否附带空格。

## 0.2.3：输入服务连接与设置入口

针对 0.2.2 收到的“选中 Monkey 后仍只有英文、没有中文候选，设置窗口也未显示”的反馈，本版调整了输入服务连接与客户端路由：

- 服务连接名统一从应用配置读取，并使用带 bundle ID 前缀的名称。
- 输入回调优先使用系统传入的客户端，避免控制器的 `client()` 暂时为空时直接放过按键。
- 设置窗口请求按实际应用路径转发，减少已安装版本与预览副本互相干扰。
- 增加服务初始化与会话路由诊断，不记录输入字符、按键码或文档内容。

已在 macOS 27.0.1 的「文本编辑」中通过实体键盘检查：候选出现，空格能输入“你好”，设置窗口也能正常打开。[0.2.3 改动与验证记录](docs/releases/0.2.3.md)

### 0.2.2：原生安装与 Apple 公证

- 双击 `Monkey Installer.app` 安装，发行包不再以裸 `.command` 脚本作为入口。
- 输入法先完成签名、公证和票据附加，再封装进同一开发者团队签名、公证的安装器。
- 安装器核对资源哈希、应用身份和开发者团队；替换前等待指定安装路径的旧版退出，失败时恢复旧版或保留备份并说明恢复路径。
- 个人词库、设置与账号连接保留，安装不会自动切换当前输入源。

0.2.2 的签名、公证和公开下载安装检查已有记录；发布后又收到上述中文输入兼容反馈。旧记录保留用于对照，当前推荐使用 0.2.3。公证验证软件的发行身份与安全检查状态，不代替中文输入和跨应用兼容性验收。[0.2.2 交付记录](docs/releases/0.2.2.md) · [安装与验证说明](docs/install.md)

### 0.2.1：入口、等待与日常操作

全新「盲 key」品牌图标与设置界面：立体青柠键帽、双拱与光标标记，去掉「猴」字标识。[视觉资源与构建说明](docs/brand.md)

- 候选条新增中译英按钮与设置齿轮，设置首页提供三步引导；普通输入采用更紧凑的候选条。
- 翻译模式下直接回车提交中文；英文仍需 `Control + Return` 明确确认，没有组合内容时回车交给当前应用。
- 候选窗只随输入出现；取消、提交或离开输入框后收起，不因仅开启翻译或切回应用而驻留。
- 翻译等待由 650 ms 缩短为 250 ms。新增可关闭的“响应优先”，在已明确支持的 GPT-6.1 Terra 上减少推理等待，保留所选模型；其他模型保持默认参数。
- 账号状态展示不再读取钥匙串，凭据仅在本进程内缓存；自动预览不弹授权提示，需授权时引导至设置中的“允许钥匙串访问”。临时签名更新后，系统仍可能要求对新版本确认一次。

[0.2.1 更新与验证记录](docs/releases/0.2.1.md)

<a id="quality"></a>

## 中文输入质量

0.2.0 集中改进了词频、排序、纠错和混输。固定语料上的自身前后对比如下：

| 指标 | 0.1.0 数据 | 0.2.0 数据 |
| :--- | ---: | ---: |
| 89 条排序语料：首选命中 | 73 / 89 | **83 / 89** |
| 89 条排序语料：前五命中 | 78 / 89 | **84 / 89** |
| 12 条错拼：首选命中 | 4 / 12 | **12 / 12** |
| 另 150 条精确拼音：前五命中 | 150 / 150 | **150 / 150** |

0.2.1 已记录 49 项本机自动测试通过。上述排序数据来自冻结的小型语料，是 Monkey 自身的配置对照，不能当作日常输入准确率，也没有与微信或搜狗进行同条件比较。纠错同时增加了计算量：本机引擎按键处理 P95 从 1.221 ms 增至 7.970 ms，未包含系统事件和界面绘制。

“两点 / 亮点”“再 / 在”等上下文同音选择、无分隔中英长串和跨应用体验仍需继续打磨。自动测试不能替代实体键盘与跨应用日常验收。

[完整质量报告与复现方法](docs/input-quality.md) · [0.2.0 交付记录](docs/releases/0.2.0.md)

## 隐私与 ChatGPT 连接

- **本地打字**：普通中文输入和词库学习不联网，不需要 ChatGPT 账号。
- **主动翻译**：开启翻译后，当前中文草稿和所选表达偏好发往 OpenAI。Monkey 不主动读取整个文档、剪贴板或其他应用内容。
- **凭据保护**：登录凭据存放在 macOS Keychain；Monkey 使用自己的授权，不读取其他应用的登录凭据。
- **订阅使用**：符合条件的 ChatGPT Plus / Pro 账号可授权使用订阅额度；模型、资格和额度以账号及服务返回为准。登录不会带入 ChatGPT 聊天记录，也不代表无限调用。[OpenAI 官方说明](https://developers.openai.com/siwc/quickstart)

[完整隐私边界](docs/privacy.md)

<a id="development"></a>

## 从源码构建

使用 Swift、InputMethodKit、AppKit / SwiftUI 与 librime。需要 Xcode 命令行工具（含支持本项目的 Swift 工具链）、Python 3，以及首次下载固定版本依赖所需的网络。

```sh
git clone https://github.com/jiaqianjing/monkey.git
cd monkey
./scripts/bootstrap-rime.sh
swift test
./scripts/build-app.sh
./scripts/install.sh
```

应用输出到 `dist/Monkey.app`。下面的命令生成供开发使用、含脚本安装器与 SHA-256 的 ZIP，不能代替上面的公证发行包：

```sh
MONKEY_CREATE_DMG=0 ./scripts/package-release.sh
```

构建脚本会检查实际架构、最低系统版本与动态依赖，并优先使用本机 Developer ID Application 身份；没有时采用 ad-hoc 签名。可用 `MONKEY_SIGNING_IDENTITY` 指定身份。正式发行使用两轮公证流程，另见 [构建与打包说明](docs/install.md#发行构建) 和 [原生安装器说明](Installer/README.md)。

## 一起打磨日常输入

欢迎通过 [Issues](https://github.com/jiaqianjing/monkey/issues/new) 提交具体例子：输入的拼音或按键顺序、实际候选、期望候选，以及 macOS 版本和使用的应用。请使用可公开的示例，避免贴出密码、私人文档或账号凭据。

<a id="support"></a>

## 请我喝杯咖啡 ☕

Monkey 免费开源，由作者持续维护。如果它让你的中文输入或英文写作更顺手，欢迎请我喝杯咖啡，支持日常测试与体验打磨。

**[爱发电 · 支持作者 ↗](https://afdian.com/a/kenjia)**

<details>
<summary>微信、支付宝与支持渠道说明</summary>

爱发电沿用作者已有主页，目前展示为「Ken · 小喷」。这里的入口用于自愿支持作者的开源维护。

<table>
  <tr>
    <td align="center"><img src="docs/assets/support/wechat.png" width="180" alt="作者现有微信收款二维码"><br>微信</td>
    <td align="center"><img src="docs/assets/support/alipay.png" width="180" alt="作者现有支付宝收款二维码"><br>支付宝</td>
  </tr>
</table>

</details>

赞助完全自愿，所有现有功能照常免费提供。ChatGPT 订阅及服务额度由对应服务商管理，赞助不包含这些费用。点一个 Star、提交可复现的问题和分享使用建议，同样是很大的支持。

## 开源与致谢

[架构说明](docs/architecture.md) · [验收清单](docs/validation.md) · [第三方声明](THIRD_PARTY_NOTICES.md)

Monkey 原创代码使用 [MIT](LICENSE)。librime、雾凇词库及其他依赖保留各自许可证；其中词库包含 GPL-3.0 数据，具体来源和许可随资源提供。
