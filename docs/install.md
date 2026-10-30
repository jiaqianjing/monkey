# 安装与打包

## 二进制开发包

**0.2.1 是未经过 Apple 公证的开发预览包。首次运行下载的 `Install.command` 时，macOS 可能显示“Apple 无法验证是否包含恶意软件”。请先阅读下方的[首次打开被 macOS 拦截](#gatekeeper)说明。**

1. 从 [GitHub Releases](https://github.com/jiaqianjing/monkey/releases/tag/v0.2.1) 下载并解压 `Monkey-0.2.1-macos-arm64.zip`。当前提供 Apple Silicon 安装包，最低系统要求为 macOS 13.0。
2. 阅读 `READ-ME.txt`，确认架构及最低 macOS 版本匹配。
3. 运行 `Install.command`，若被拦截，按下方说明处理。它将 Monkey 安装到 `~/Library/Input Methods/Monkey.app`，不需要 `sudo`，也不会修改其他输入法；系统的安全确认可能另外要求密码或 Touch ID。
4. 从菜单栏输入法菜单选择 Monkey 拼音。安装不会自动切换输入源。
5. 若未出现，注销 macOS 用户再登录，在系统设置 → 键盘 → 文字输入 → 编辑中添加 Monkey。

<a id="gatekeeper"></a>

### 首次打开被 macOS 拦截

如果弹窗只有「完成」和「移到废纸篓」，并提示 **“Apple 无法验证 ‘Install.command’ 是否包含可能危害 Mac 安全或泄漏隐私的恶意软件”**，表示系统无法完成该下载文件的安全验证。当前预览应用使用 ad-hoc 签名，未经过 Apple 公证。

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

先结束正在编辑的组合文本。下载新版 ZIP 并运行其中的 `Install.command`，或重新构建后运行安装脚本。它会要求旧 Monkey 进程退出，再替换该应用。用户数据不会被覆盖。更新后若 macOS 仍运行旧版本，请注销再登录。

## 状态检查

```sh
"$HOME/Library/Input Methods/Monkey.app/Contents/MacOS/MonkeyInputMethod" --list-input-sources
cat "$HOME/Library/Input Methods/Monkey.app/Contents/Resources/BUILD-INFO.txt"
codesign --verify --deep --strict "$HOME/Library/Input Methods/Monkey.app"
```

注册成功表示 macOS 接受了注册命令，不代表已经选中输入法，也不代替在具体应用里的实际打字验收。

## 发行构建

```sh
./scripts/package-release.sh
```

输出 ZIP 和 SHA-256 文件，并尽力生成可选 DMG。先使用兼容旧系统的 `hdiutil`，失败时若系统提供新版 `diskutil image` 则重试；镜像服务仍失败时不保留不完整 DMG，ZIP 仍可独立安装。设置 `MONKEY_CREATE_DMG=0` 可直接仅生成 ZIP；`--skip-build` 可打包已存在且验证通过的 `dist/Monkey.app`。

```sh
MONKEY_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/package-release.sh
```

Developer ID 签名不会自动使应用获得公证。向普通用户正式分发前，应使用自己的有效 Developer ID 完成签名、公证及发行包实际安装验证。仓库 CI 产物属于 ad-hoc 签名开发包。

## 卸载

运行发行目录的 `Uninstall.command`，或源码中的 `scripts/uninstall.sh`。脚本核对 bundle ID 后，仅停用、退出并删除 Monkey.app。用户词库、偏好和 Keychain 凭据保留；如需断开账号，应先通过设置完成。

## 参考

- [Apple：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)
- [Apple InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [IMKServer 的 Info.plist 配置](https://developer.apple.com/documentation/inputmethodkit/imkserver/init(name:bundleidentifier:))
- [Squirrel 官方安装说明](https://github.com/rime/squirrel#安裝輸入法)
