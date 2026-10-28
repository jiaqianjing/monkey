# 架构与交互边界

Monkey 是真正的 macOS InputMethodKit 输入法。系统通过 `Monkey_Connection` 创建 `MonkeyInputController`，控制器管理当前输入会话；主程序也提供 `--settings` 独立设置入口。

```text
macOS 文本输入框
    ↕ InputMethodKit
MonkeyInputController ── 拼音候选与中文草稿
    ├─ MonkeyPinyin → CRimeBridge → librime
    └─ MonkeyCore → 订阅授权 / 翻译请求
                        ↕
                   OpenAI Responses API
MonkeySettings ── SwiftUI 设置与浏览器登录
```

## 本地拼音

拼音按键同步交给 librime，结果由 InputMethodKit 上屏。词库及配置在应用的 `Contents/Resources/Rime`，运行库在 `Contents/Frameworks`。用户词学习使用独立用户目录，不占用鼠须管的用户词库。

首版采用雾凇词库的基础全拼配置，不包含其所有 Lua 插件和扩展功能。主程序使用运行时加载；安装后的应用不需要 Homebrew 或额外的词库服务。

## 翻译会话

正常模式按通常拼音方式直接上屏。翻译模式下，拼音选词进入中文草稿，后台请求英文预览。普通空格仍是选词；英文由 `Control + Return` 确认，中文由 `Shift + Return` 确认。

每次草稿修改都产生新版本。返回的翻译只有同时匹配当前输入会话、目标文本客户端和文稿版本时才可采用。取消、焦点变化、断网或流中断都不构成翻译成功；旧结果不能写入新输入框。

首版草稿按句追加和回删。它不是可任意移动光标、多段编辑的完整文字编辑器。已经上屏的内容由宿主应用管理，Monkey 不跨应用自动修改已提交文本。

## 订阅连接

使用 OpenAI 官方 [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source)；系统浏览器完成授权，本机 loopback 回调接收授权码。应用管理 PKCE、状态校验、账号与令牌存储。凭据保存在 Keychain，设置窗口只显示账号状态。

模型来自已登录账号的目录。推理使用公开 Responses API，按当前订阅接入契约设置 `store: false`、`stream: true`。只有收到完成事件才将译文标为可确认；流中途仍可能返回用量限制或错误。

## 分发

Bundle ID：`org.monkey.inputmethod.Monkey`；输入模式：`org.monkey.inputmethod.Monkey.Hans`。Info.plist 的控制器类、连接名和代码必须一致。

签名、安装、注册、选中输入法、实际输入、ChatGPT 授权、成功翻译属于独立验证阶段。构建通过并不证明后续阶段已经完成。
