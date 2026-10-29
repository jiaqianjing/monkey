# 安装与打包

## 二进制开发包

1. 从 [GitHub Releases](https://github.com/jiaqianjing/monkey/releases/tag/v0.2.0) 下载并解压 `Monkey-0.2.0-macos-arm64.zip`。当前提供 Apple Silicon 安装包，最低系统要求为 macOS 13.0。
2. 阅读 `READ-ME.txt`，确认架构及最低 macOS 版本匹配。
3. 运行 `Install.command`。它只写入 `~/Library/Input Methods/Monkey.app`，不需要管理员密码，也不会修改其他输入法。
4. 从菜单栏输入法菜单选择 Monkey 拼音。安装不会自动切换输入源。
5. 若未出现，注销 macOS 用户再登录，在系统设置 → 键盘 → 文字输入 → 编辑中添加 Monkey。

当前预览包使用 ad-hoc 签名，未经过 Apple 公证。若 Gatekeeper 拦截下载的开发包，可自行从源码构建，或在确认来源后使用 macOS 提供的打开/隐私与安全性流程；不需要关闭系统安全功能。脚本不会清除 quarantine 属性或绕过 Gatekeeper。

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

- [Apple InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [IMKServer 的 Info.plist 配置](https://developer.apple.com/documentation/inputmethodkit/imkserver/init(name:bundleidentifier:))
- [Squirrel 官方安装说明](https://github.com/rime/squirrel#安裝輸入法)
