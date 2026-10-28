# Monkey 拼音

macOS 原生中文拼音输入法，支持在当前输入框里用中文写作、预览英文并确认上屏。

0.1.0 是首个开发预览版。项目使用 Swift、InputMethodKit 和 librime；中文词库来自雾凇拼音。日常拼音输入在本地完成，翻译通过用户明确连接的 ChatGPT 账号执行。

## 当前范围

- 中文全拼、简拼、整句候选、选词与本地用户词学习。
- 在输入法内切换中译英模式，保留中文草稿并显示英文预览。
- 英文确认后才上屏；断网、额度不足或登录失效时保留原文。
- 官方 Sign in with ChatGPT 登录，使用符合条件账号授权的 ChatGPT 订阅额度，无需填写 API key。
- 设置窗口管理账号、模型和翻译偏好。

ChatGPT 登录不等于无限调用，也不会让本地拼音引擎自动拥有 ChatGPT 的记忆或聊天记录。可用模型、资格与额度以登录账号和服务返回为准。[官方接入说明](https://developers.openai.com/siwc/token-sharing-open-source)。

首版重点是中文输入与中译英流程。基础拼音体验尚未通过长期日常试用证明可替代微信或搜狗；跨应用兼容性和真实翻译延迟仍需持续验证。

## 安装

源码目标为 macOS 13+。每个二进制包会扫描实际依赖的最低系统版本，具体要求见包内 `READ-ME.txt` 与 `Monkey.app/Contents/Resources/BUILD-INFO.txt`。首个本地交付包为 Apple Silicon（arm64）。

下载并解压发行包后，运行 `Install.command`。安装目标只有：

```text
~/Library/Input Methods/Monkey.app
```

安装器注册并启用 Monkey，不切换当前输入源。随后从菜单栏输入法菜单选择 **Monkey 拼音**；若没有出现，在系统设置 → 键盘 → 文字输入 → 编辑中添加。首次安装后若未显示或部分应用无法输入，请注销当前 macOS 用户再登录。

开发预览包未经过 Apple 公证；当前本地构建使用临时签名（ad-hoc）。它不是已通过 Gatekeeper 认证的公开发行版。安装与自行构建的详细步骤见 [安装说明](docs/install.md)。

## 使用

| 操作 | 快捷键 |
| --- | --- |
| 拼音选首个候选 | 空格 |
| 按编号选词 | 数字键 |
| 切换中文拼音 / 英文直输 | `Shift + Space` |
| 开关中译英模式 | `Control + Shift + T` |
| 确认当前英文上屏 | `Control + Return` |
| 将中文原文上屏 | `Shift + Return` |
| 清除当前拼音，或取消翻译请求并保留中文 | `Esc` |

翻译模式中的选词会进入当前中文草稿。英文预览随草稿更新，只有当前版本翻译完成后才能确认。切换输入框时，旧请求不得向新输入框写入内容。

打开设置：

```sh
open -a "$HOME/Library/Input Methods/Monkey.app" --args --settings
```

在设置中选择 **Continue with ChatGPT**，由系统浏览器完成 OpenAI 登录和授权。密码、验证码及授权确认由你本人操作。首次使用需实际完成一次翻译，才能确认该账号拥有当前请求所需权限。

## 从源码构建

需要 Xcode 命令行工具（含支持本项目的 Swift 工具链）、Python 3，以及联网下载固定版本的 librime 运行库。

```sh
./scripts/bootstrap-rime.sh
swift test
./scripts/build-app.sh
./scripts/install.sh
```

构建输出位于 `dist/Monkey.app`。生成含安装器的 ZIP 和 DMG：

```sh
./scripts/package-release.sh
```

脚本会优先使用本机可用的 Developer ID Application 身份；没有时使用 ad-hoc 签名。也可通过 `MONKEY_SIGNING_IDENTITY` 指定签名身份。签名和公证是不同步骤，本项目脚本不会自动提交 Apple 公证。

## 隐私和数据

普通拼音输入无需网络。启用翻译后，当前中文草稿和选择的表达偏好会发往 OpenAI；Monkey 不主动读取整个文档、剪贴板或其他应用内容。登录凭据保存在 macOS Keychain。详见 [隐私边界](docs/privacy.md)。

卸载输入法：

```sh
./scripts/uninstall.sh
```

卸载保留用户词库、偏好及保存的账号连接。如需删除凭据，请先在 Monkey 设置中断开账号。

## 开发与许可证

[架构说明](docs/architecture.md) · [验收清单](docs/validation.md) · [第三方声明](THIRD_PARTY_NOTICES.md)

Monkey 原创程序代码使用 [MIT](LICENSE)。librime、词库及其依赖保持各自许可证；雾凇词库包含 GPL-3.0 数据，具体来源及许可随资源保留。不要将根目录 MIT 许可证理解为第三方资源也改用了 MIT。
