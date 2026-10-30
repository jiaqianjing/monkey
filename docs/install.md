# 安装与打包

## 0.2.2 原生安装包

当前提供 Apple Silicon（arm64）安装包，最低系统要求为 macOS 13.0。安装器和输入法均使用 Developer ID 签名，通过 Apple 公证并附带公证票据（stapled）；不需要在系统安全设置中为新版手动添加打开例外。macOS 仍可能显示正常的首次下载确认。

1. 从 [GitHub Releases](https://github.com/jiaqianjing/monkey/releases/tag/v0.2.2) 下载并解压 `Monkey-0.2.2-macos-arm64-notarized.zip`。
2. 阅读包内 `README.txt`，双击 **`Monkey Installer.app`**，在窗口中点击 **安装**。新版不使用 `Install.command` 作为入口。
3. 安装位置为 `~/Library/Input Methods/Monkey.app`，不需要 `sudo`。安装器会验证资源、应用身份和开发者团队，再注册并启用输入法，不会自动切换当前输入源。
4. 从菜单栏输入法菜单手动选择 **Monkey 拼音**。若没有出现，在 **系统设置 → 键盘 → 文字输入 → 编辑** 中添加。
5. 如果安装器提示当前登录会话尚未完成注册，或首次安装、更新后仍无法输入，请注销当前 macOS 用户再登录，再添加 Monkey。
6. 如需翻译，点击安装器的 **打开 Monkey 设置**，由你本人完成 ChatGPT 登录及授权。普通拼音输入无需连接账号。

安装器不会删除用户词库、偏好或账号连接。从旧版临时签名迁移后，macOS 仍可能要求重新确认钥匙串访问；这是凭据授权，与“仍要打开”的 Gatekeeper 例外不同。

若新版仍出现“Apple 无法验证”或“已损坏”，先核对下载版本、文件校验值及提示针对的文件，并反馈具体 macOS 版本和提示。不要直接套用下方旧包的放行步骤。受组织管理的 Mac 还可能有额外安装策略。

### 核对下载文件

解压前，将 ZIP 与 [SHA-256 文件](https://github.com/jiaqianjing/monkey/releases/download/v0.2.2/Monkey-0.2.2-macos-arm64-notarized.sha256) 下载到同一目录，在该目录打开终端运行：

```sh
shasum -a 256 -c Monkey-0.2.2-macos-arm64-notarized.sha256
```

应显示 `Monkey-0.2.2-macos-arm64-notarized.zip: OK`。校验值用于核对下载与发布附件一致；代码签名、Apple 公证和实际安装验收仍是各自独立的检查。

### 验证范围

正式发行会分别核对输入法和安装器的签名、公证票据，以及 ZIP 解压后的完整性。当前 Mac 上的工具检查、真实下载安装与使用观测，只能证明对应本机环境；不能当作另一台干净 Mac、全新 VM 或 macOS 13 等所有支持系统的首次安装验收。输入法跨应用和实体键盘验收另见[验收记录](validation.md)。

<a id="legacy-preview"></a>

## 旧版预览包与回退

[0.2.1 开发预览](https://github.com/jiaqianjing/monkey/releases/tag/v0.2.1) 保留供回退和问题对照。它是 ad-hoc 签名、未经过 Apple 公证的旧包，使用 `Monkey-0.2.1-macos-arm64.zip` 和 `Install.command`；以下 Gatekeeper 步骤仅针对这类旧包。

如需从 0.2.2 回退，先结束当前输入并退出 Monkey 设置，再解压 0.2.1 包并运行其 `Install.command`。旧安装脚本会替换程序，保留用户词库、偏好和账号连接；回退后可能需要注销再登录，并重新确认钥匙串访问。新版原生安装器会拒绝用较低版本或同版本较低 build 覆盖现有程序。

<a id="gatekeeper"></a>

### 旧包首次打开被 macOS 拦截

如果旧包的弹窗只有「完成」和「移到废纸篓」，并提示 **“Apple 无法验证 ‘Install.command’ 是否包含可能危害 Mac 安全或泄漏隐私的恶意软件”**，表示系统无法完成该下载文件的安全验证。0.2.1 及更早预览包中的应用使用 ad-hoc 签名，未经过 Apple 公证。

仅在确认下载来自本仓库的 Releases、且文件未被改动后，按 [Apple 官方打开流程](https://support.apple.com/zh-cn/102445) 操作：

1. 在当前弹窗中点 **「完成」**。
2. 打开 **系统设置 → 隐私与安全性**，向下滚动到 **「安全性」**。
3. 找到针对 **`Install.command`** 的拦截记录，点 **「仍要打开」**。
4. 亲自完成系统要求的身份验证，并在再次弹出的提示中点 **「打开」**。安装脚本随后会在终端运行。

若没有看到「仍要打开」，先重新双击一次 `Install.command` 触发拦截，再查看该设置页面。受组织管理的 Mac 可能不允许添加例外，需要由管理员处理。

**如果随后又拦截 `Monkey.app`：** 它与安装脚本是分别检查的文件，仍可能需要单独确认。对提示中对应的 Monkey 使用同样的「隐私与安全性 → 仍要打开」流程，再重新运行同一目录里的 `Install.command`，让注册和启用命令完成。若仅出现 `Installed:`，但同时显示 `macOS did not finish registering/enabling...`，说明应用已经复制，输入法注册仍未完成。

上述操作为指定文件添加打开例外，不需要关闭系统门禁。安装脚本不会移除 quarantine 属性。也可以选择[从源码构建](#从源码安装)。

如需先核对下载文件，在解压前将 ZIP 和对应 `.sha256` 文件下载到同一目录，在该目录打开终端并运行：

```sh
shasum -a 256 -c Monkey-0.2.1-macos-arm64.sha256
```

应显示 `Monkey-0.2.1-macos-arm64.zip: OK`。校验用于核对文件与发布包一致，不能代替 Apple 公证。

DMG 是文件分发容器，不是系统安装器。若直接在只读 DMG 中运行安装脚本被系统策略拦截，先将完整目录复制到本机，再运行。

## 从源码安装

```sh
./scripts/bootstrap-rime.sh
swift test
./scripts/build-app.sh
./scripts/install.sh
```

`bootstrap-rime.sh` 下载固定版本的官方 macOS universal 运行库，并校验 SHA-256。构建时依赖会复制到 `Contents/Frameworks`，不需要使用者安装 Homebrew。

`build-app.sh` 执行以下检查：

- 主程序和 dylib 包含当前构建架构。
- 非系统动态依赖全部在包内，避免依赖开发机绝对路径。
- 读取所有 Mach-O 的实际最低系统版本，并更新最终 Info.plist。
- 从内到外签名运行库和应用，再执行严格签名验证。

Swift 源码目标为 macOS 13，运行库或未来其他依赖若要求更高版本，最终包会如实提高最低系统要求，而不是仅沿用源码声明。

## 更新

先结束正在编辑的组合文本并退出 Monkey 设置。下载新版公证 ZIP，解压后打开 `Monkey Installer.app`，点击安装。安装器仅请求指定安装路径的旧版 Monkey 正常退出，等待退出后才替换；若进程仍在运行，会停止并提示重试，不会强行结束它。

安装器验证新程序后再注册、启用输入法。可恢复的硬错误会恢复旧版；若自动恢复被其他操作阻止，会保留备份并显示恢复路径。用户词库、偏好和 Keychain 凭据不在替换范围内。更新后若 macOS 仍运行旧版本，请注销再登录。

从源码安装的用户仍可重新构建后运行 `scripts/install.sh`；它是开发脚本，与发行包中的原生安装器不同。

## 状态检查

```sh
"$HOME/Library/Input Methods/Monkey.app/Contents/MacOS/MonkeyInputMethod" --list-input-sources
cat "$HOME/Library/Input Methods/Monkey.app/Contents/Resources/BUILD-INFO.txt"
codesign --verify --deep --strict "$HOME/Library/Input Methods/Monkey.app"
xcrun stapler validate "$HOME/Library/Input Methods/Monkey.app"
spctl --assess --type execute --verbose=4 "$HOME/Library/Input Methods/Monkey.app"
```

后三项分别核对签名完整性、公证票据和本机 Gatekeeper 评估；`stapler` 是维护者或已安装 Xcode 命令行工具用户的诊断命令，普通安装不需要安装 Xcode。旧 ad-hoc 包没有 Apple 公证票据。注册成功表示 macOS 接受了注册命令，不代表已经选中输入法，也不代替在具体应用里的实际打字验收。

## 发行构建

### 公证发行包

正式发行使用有效的 **Developer ID Application** 身份，并完成两轮流程：先对输入法签名、公证和附加票据；再把该输入法封装进同一团队签名的 `Monkey Installer.app`，对安装器公证并附加票据；最后生成 ZIP 与 SHA-256，解压复核安装器和嵌入输入法。发行包不包含供用户双击运行的 `.command` 入口。

`scripts/notarize-release.sh` 是维护者使用的独立流水线。它要求显式配置签名身份和公证凭据，检查两轮服务返回及最终解包产物；不安装、不自动发布。使用已经配置的 Keychain 公证凭据示例：

```sh
MONKEY_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MONKEY_NOTARY_PROFILE='monkey-release' \
./scripts/notarize-release.sh
```

也可以通过 Xcode 的 Developer ID / Direct Distribution 上传与导出流程完成公证，再按相同顺序封装。无论哪条路径，都应保存 Apple 返回的提交与通过记录、验证票据，并使用最终下载文件进行安装检查。Developer ID 签名本身不会自动使应用获得公证。[原生安装器与两轮封装说明](../Installer/README.md)

### 开发用归档

```sh
./scripts/package-release.sh
```

这条命令生成开发用 ZIP、SHA-256 和脚本安装器，并尽力生成可选 DMG，不执行 Apple 公证。先使用兼容旧系统的 `hdiutil`，失败时若系统提供新版 `diskutil image` 则重试；镜像服务仍失败时不保留不完整 DMG，ZIP 仍可独立安装。设置 `MONKEY_CREATE_DMG=0` 可直接仅生成 ZIP；`--skip-build` 可打包已存在且验证通过的 `dist/Monkey.app`。

```sh
MONKEY_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/package-release.sh
```

没有 Developer ID 时，本地开发构建使用 ad-hoc 签名。仓库 CI 产物也属于 ad-hoc 签名开发包，不能与带 `-notarized` 文件名的正式发布附件混为一谈。

## 卸载

新版原生安装包不包含 `Uninstall.command`。如需卸载，可获取本仓库源码，在仓库根目录运行 `./scripts/uninstall.sh`；旧预览包也可运行原目录的 `Uninstall.command`。脚本核对 bundle ID 后，仅停用、退出并删除 Monkey.app。用户词库、偏好和 Keychain 凭据保留；如需断开账号，应先通过设置完成。

## 参考

- [Apple：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)
- [Apple InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [IMKServer 的 Info.plist 配置](https://developer.apple.com/documentation/inputmethodkit/imkserver/init(name:bundleidentifier:))
- [Squirrel 官方安装说明](https://github.com/rime/squirrel#安裝輸入法)
