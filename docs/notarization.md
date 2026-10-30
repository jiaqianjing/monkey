# Developer ID 签名与 Apple 公证

正式发行与 CI 的开发预览包分别构建。缺少发行证书、公证凭据或验证失败时，正式发行流程会终止，不会自动改用 ad-hoc 签名。

## 发行身份与凭据

- 应用、运行库与原生安装器使用 **Developer ID Application**，启用 Hardened Runtime 与安全时间戳；Apple Development 和 Apple Distribution 不能代替这个证书。
- 签名私钥保存在维护者的本机钥匙串，不上传到仓库或 Release。
- 公证认证使用显式指定的 `notarytool` 钥匙串配置，或者 App Store Connect API key。凭据、私钥文件和应用专用密码均不写入源码、日志或 GitHub 附件。
- Xcode 已登录账号时，也可使用其正常的 Developer ID 归档上传、公证和导出流程。不要提取 Xcode 登录令牌作为脚本凭据。

在维护者自己的终端交互配置公证凭据，按 `xcrun notarytool store-credentials --help` 操作。例如，提供 Apple Account 和 Team ID、**省略 `--password`**，由工具安全提示输入应用专用密码：

```sh
xcrun notarytool store-credentials MonkeyNotary \
  --apple-id YOUR_APPLE_ACCOUNT --team-id YOUR_TEAM_ID
```

## 双轮公证与打包

```sh
MONKEY_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
MONKEY_NOTARY_PROFILE=MonkeyNotary \
./scripts/notarize-release.sh
```

流程按 [Apple 对自定义安装器的要求](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)执行：

1. 构建输入法，从内到外签名运行库与 `Monkey.app`，检查证书类型、Team ID、安全时间戳、Hardened Runtime 和实际架构。
2. 提交输入法 ZIP，等待 `Accepted` 并核对公证日志；为 `Monkey.app` 附加票据并验证。
3. 将已附票据的输入法放入原生 `Monkey Installer.app`，签名安装器，再完成安装器的公证及票据验证。
4. 对两个应用执行 Gatekeeper 检查；系统提供 `syspolicy_check` 时，同时检查分发状态。
5. 从已附票据的安装器生成最终 ZIP，再解压检查安装器及内嵌输入法；生成 SHA-256 和本地验证记录。ZIP 自身不支持附加公证票据。

最终 ZIP 使用 `-notarized.zip` 后缀，默认保存到 `dist/notarized/`。正式用户入口为原生安装器，不要求运行裸 `Install.command`。如另外生成 DMG，则 DMG 本身也需签名、公证并附加票据。

超时或中断时，保留提交 ID、状态和日志；使用脚本输出的工作目录恢复，避免重复上传：

```sh
./scripts/notarize-release.sh --resume /absolute/path/to/preserved/workflow
```

上传成功不等于公证成功。只有 `Accepted`、票据验证、签名与 Gatekeeper 检查均通过后，才能把该附件标为已公证。

## 安装与发布验收

原生安装器只在用户点击「安装」后写入当前用户的 `~/Library/Input Methods/Monkey.app`。它验证 payload 身份和完整性，保留词库、偏好与账号数据；更新失败时提供明确状态。开发模式安装器禁用安装，不能当作正式发行包。

发布前应通过浏览器下载最终附件，在干净的 Mac 或虚拟机中保留下载隔离属性，检查首次打开、安装、输入源选择和离线票据验证。已有开发机允许记录的命令行检查，不能代替这项验收。[Apple：Testing a Notarised Product](https://developer.apple.com/forums/thread/130560)

已公证版本仍可能显示正常的“从互联网下载，是否打开”确认；这与要求用户到安全设置添加例外不同。旧 ad-hoc 版本升级为 Developer ID 身份时，原有 ChatGPT 凭据可能需要用户单独重新授权钥匙串访问。

正式 Release 应附上版本、架构、最低系统要求、最终校验值和实际验证结果。旧版附件与校验值保留，避免原地替换已下载用户依赖的文件。
