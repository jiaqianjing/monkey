import AppKit
import MonkeyCore
import SwiftUI

@MainActor
public struct MonkeySettingsView: View {
    @ObservedObject private var client: ChatGPTClient
    @State private var selection: SettingsSection = .start

    public init() { self.client = .shared }
    public init(client: ChatGPTClient) { self.client = client }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Text("猴").font(.system(size: 27, weight: .semibold, design: .rounded))
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Monkey").font(.system(size: 21, weight: .bold, design: .rounded))
                        Text("中文输入 · 自然英文").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 5) {
                    ForEach(SettingsSection.allCases) { section in
                        Button { selection = section } label: {
                            Label(section.title, systemImage: section.icon)
                                .font(.system(size: 13, weight: selection == section ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                                .background(selection == section ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == section ? .isSelected : [])
                    }
                }
                Spacer()
                Label(client.accountEmail == nil ? "普通输入离线可用" : (client.requiresKeychainAuthorization ? "ChatGPT 连接待授权" : "ChatGPT 连接已保存"),
                      systemImage: client.accountEmail == nil ? "keyboard" : (client.requiresKeychainAuthorization ? "key" : "person.crop.circle"))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") · 开源 macOS 输入法")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(22).frame(width: 240).background(.ultraThinMaterial)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(selection.heading).font(.system(size: 27, weight: .bold))
                        Text(selection.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    switch selection {
                    case .start:
                        StartPane(isConnected: client.accountEmail != nil,
                                  onConnect: { selection = .account },
                                  onTryTranslation: { selection = .translation })
                    case .typing: TypingPane()
                    case .account: AccountPane(client: client)
                    case .translation: TranslationPane(client: client)
                    case .privacy: PrivacyPane()
                    }
                }
                .padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 840, idealWidth: 920, minHeight: 640, idealHeight: 720)
        .onAppear { client.reloadAccount() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: ChatGPTClient.accountChangedNotification)) { _ in client.reloadAccount() }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case start, typing, account, translation, privacy
    var id: Self { self }
    var title: String {
        switch self { case .start: return "开始使用"; case .typing: return "中文输入"; case .account: return "ChatGPT 账号"; case .translation: return "翻译试写"; case .privacy: return "隐私与快捷键" }
    }
    var icon: String {
        switch self { case .start: return "keyboard"; case .typing: return "character.cursor.ibeam"; case .account: return "person.crop.circle"; case .translation: return "character.bubble"; case .privacy: return "hand.raised" }
    }
    var heading: String {
        switch self { case .start: return "用中文，写出你的想法。"; case .typing: return "让中文输入更顺手。"; case .account: return "带上你的 ChatGPT。"; case .translation: return "先在这里试写一句。"; case .privacy: return "你的文字，由你决定。" }
    }
    var subtitle: String {
        switch self { case .start: return "本地拼音输入，加上随时开启的中译英。"; case .typing: return "按你的习惯选择候选布局与英文混输方式。"; case .account: return "通过官方登录授权，使用账号可用的订阅额度。"; case .translation: return "查看翻译质量与连接状态，再回到任何应用里写作。"; case .privacy: return "普通输入留在本机；翻译只发送当前草稿。" }
    }
}

private struct SettingsCard<Content: View>: View {
    private let title: String
    private let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }
}

private struct StartPane: View {
    let isConnected: Bool
    let onConnect: () -> Void
    let onTryTranslation: () -> Void

    var body: some View {
        SettingsCard("中译英，就在候选窗里") {
            GuideStep(number: "1", title: isConnected ? "账号连接已保存" : "先连接你的 ChatGPT",
                      detail: "登录一次，再回到你正在写字的输入框。登录本身不会自动开启翻译。")
            GuideStep(number: "2", title: "点候选窗里的「中译英」",
                      detail: "也可按 ⌃⇧T。看到「中 → 英」后，照常用拼音选词，英文会在窗口里预览。候选窗只在输入时出现。")
            GuideStep(number: "3", title: "回车输入中文，⌃↩ 输入英文",
                      detail: "Return 直接提交本句中文，不必等译文；Control Return 只提交已经完成的英文。Shift Return 也可提交中文。")
            HStack {
                Button(isConnected ? "管理 ChatGPT 连接" : "连接 ChatGPT", systemImage: "person.crop.circle") { onConnect() }
                    .buttonStyle(.borderedProminent)
                Button("先在这里试译一句", systemImage: "character.bubble") { onTryTranslation() }
                    .disabled(!isConnected)
            }
            Text("只有主动开启中译英后，当前草稿才会发送至 OpenAI。普通拼音输入始终在本机完成。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        SettingsCard("1　添加 Monkey 输入源") {
            Text("安装后，在「系统设置 → 键盘 → 文字输入 → 编辑 → ＋ → 简体中文」中添加 Monkey。如果列表里尚未出现，请退出登录 macOS 后重新登录。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("打开键盘设置", systemImage: "gear") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
        }
        SettingsCard("2　像往常一样打中文") {
            Text("从菜单栏切换到 Monkey。用全拼或简拼输入，空格或数字选词，PgUp / PgDn 或 - / = 翻页。普通模式下，Return 原样输入当前拼音或英文。按 ⇧ Space 切换中英文；翻译模式下输入的英文原样加入草稿。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("在「中文输入」中选择候选布局和英文空格习惯。常用候选根据本机选词学习，数字、网址、邮箱与版本号中的 ASCII 符号保留原样。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.callout.weight(.semibold))
                .frame(width: 25, height: 25)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct TypingPane: View {
    @AppStorage("typing.automaticEnglish", store: TypingPreferences.defaults) private var automaticEnglish = true
    @AppStorage("typing.horizontalCandidates", store: TypingPreferences.defaults) private var horizontalCandidates = true
    @AppStorage("typing.englishSpaceInsertsSpace", store: TypingPreferences.defaults) private var englishSpaceInsertsSpace = true
    @State private var folderMessage: String?

    var body: some View {
        SettingsCard("候选与英文混输") {
            Toggle(isOn: $automaticEnglish) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动识别常见英文产品词").font(.callout.weight(.medium))
                    Text("例如 macOS、GitHub。其他拼音或英文仍可按 Return 原样输入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Divider()
            Toggle(isOn: $horizontalCandidates) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("横排候选").font(.callout.weight(.medium))
                    Text("开启时横向排列候选；关闭后改为纵向排列。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Divider()
            Toggle(isOn: $englishSpaceInsertsSpace) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("英文片段按 Space 保留空格").font(.callout.weight(.medium))
                    Text("开启时，空格确认英文片段并保留一个空格。Return 确认原文不加空格；关闭后，空格只确认候选。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Text("数字、网址、邮箱和版本号中的 ASCII 符号会保留原样；普通中文输入仍使用中文标点。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        SettingsCard("本机词库与学习") {
            Text("常用候选的排序会根据你在本机的选词逐渐学习。在候选窗口右键某个词，可删除该词的学习记录；基础词库中的词条仍可能出现。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("打开本机词库文件夹", systemImage: "folder") { openUserDictionary() }
            if let folderMessage {
                Text(folderMessage).font(.caption).foregroundStyle(.secondary)
            }
            Text("此操作只打开文件夹，不会清空或重置你的词库。")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func openUserDictionary() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monkey/Rime", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            folderMessage = "词库文件夹会在首次使用 Monkey 拼音后建立。"
            return
        }
        folderMessage = NSWorkspace.shared.open(folder) ? nil : "暂时无法打开词库文件夹，请稍后重试。"
    }
}

@MainActor
private struct AccountPane: View {
    @ObservedObject var client: ChatGPTClient
    @State private var actionMessage: String?
    @State private var isWorking = false
    var body: some View {
        SettingsCard("ChatGPT 连接") {
            if let email = client.accountEmail {
                Label(email, systemImage: client.requiresKeychainAuthorization ? "key" : "person.crop.circle").font(.headline)
            } else {
                Label("尚未连接", systemImage: "person.crop.circle.badge.questionmark").foregroundStyle(.secondary)
            }
            Text(actionMessage ?? client.statusMessage).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button(client.isSigningIn ? "正在等待浏览器…" : "Continue with ChatGPT") {
                    run { try await client.signIn() }
                }
                .buttonStyle(.borderedProminent).disabled(isWorking || client.isSigningIn)
                if client.isSigningIn { Button("取消") { client.cancelSignIn() } }
                if client.accountEmail != nil {
                    Button("退出登录") { run { try await client.signOut() } }.disabled(isWorking)
                }
            }
            if client.activeAccountID != nil && !client.accounts.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Button("允许钥匙串访问", systemImage: "key") {
                        run { try await client.authorizeKeychainAccess() }
                    }
                    .disabled(isWorking || client.isSigningIn)
                    Text(client.requiresKeychainAuthorization ? "需要你允许 Monkey 读取已保存的登录凭据。点击按钮后，请亲自处理 macOS 的授权提示。" : "首次翻译或更新后，macOS 可能要求访问已保存的登录凭据。若先前拒绝，可在这里主动重试。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("需要符合条件的 ChatGPT 套餐，并单独允许订阅使用权限。登录不会授权读取你的 ChatGPT 聊天记录。")
                .font(.caption).foregroundStyle(.secondary)
            Link("在 ChatGPT 中管理用量与授权 ↗", destination: URL(string: "https://chatgpt.com/settings/usage")!).font(.callout)
        }
        if !client.accounts.isEmpty {
            SettingsCard("已保存的连接") {
                ForEach(client.accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.email).font(.callout)
                            Text(String(account.clientID.suffix(12))).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if client.activeAccountID == account.clientID { Text("当前连接").font(.caption).foregroundStyle(.secondary) }
                        else { Button("选择") { client.selectAccount(account.clientID) }.disabled(isWorking) }
                    }
                }
                Button("添加其他账号或工作区") { run { try await client.signIn(asNewAccount: true) } }.disabled(isWorking)
            }
        }
        SettingsCard("翻译模型") {
            if client.models.isEmpty {
                Text("登录后从账号获取可用模型。模型出现在列表中，不代表每次请求都一定有可用额度。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("模型", selection: $client.selectedModel) {
                    ForEach(client.models) { model in Text(model.displayName).tag(model.slug) }
                }.labelsHidden()
            }
            Button("刷新可用模型", systemImage: "arrow.clockwise") { run { try await client.refreshModels() } }
                .disabled(client.accountEmail == nil || isWorking)
        }
    }
    private func run(_ action: @escaping () async throws -> Void) {
        actionMessage = nil; isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do { try await action() } catch { actionMessage = ChatGPTClient.userMessage(error) }
        }
    }
}

@MainActor
private struct TranslationPane: View {
    @ObservedObject var client: ChatGPTClient
    @AppStorage("translationTone", store: ChatGPTClient.defaults) private var tone = "natural"
    @AppStorage("translation.preferSpeed", store: ChatGPTClient.defaults) private var preferSpeed = true
    @State private var draft = "明天下午我有空，我们把会议改到三点吧。"
    @State private var result = ""
    @State private var errorMessage: String?
    @State private var isTranslating = false
    @State private var completed = false
    @State private var latency: TranslationLatency?
    @State private var translationTask: Task<Void, Never>?
    var body: some View {
        SettingsCard("中文草稿") {
            TextEditor(text: $draft).font(.system(size: 15)).frame(minHeight: 110)
                .accessibilityLabel("待翻译中文草稿")
            HStack {
                Picker("表达语气", selection: $tone) { Text("自然日常").tag("natural"); Text("简洁商务").tag("business") }.frame(width: 220)
                Spacer()
                if isTranslating {
                    ProgressView().controlSize(.small)
                    Button("取消") { translationTask?.cancel() }
                } else {
                    Button("翻译为英文", systemImage: "arrow.down") { translate() }
                        .buttonStyle(.borderedProminent).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.accountEmail == nil)
                }
            }
            Toggle(isOn: $preferSpeed) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("响应优先").font(.callout.weight(.medium))
                    Text("日常翻译优先更快显示，仍使用你选择的模型；关闭后使用模型默认设置。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            if TranslationRequestPolicy.reasoningEffort(model: client.selectedModel, preferSpeed: true) == nil {
                Text("当前模型沿用默认响应设置；响应优先目前支持 GPT-6.1 Terra。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if client.accountEmail == nil { Text("先到「ChatGPT 账号」完成登录。中文草稿会保留在本页。 ").font(.caption).foregroundStyle(.secondary) }
        }
        SettingsCard(completed ? "英文译文" : "英文预览") {
            Text(result.isEmpty ? "译文会显示在这里。" : result).font(.system(size: 16)).lineSpacing(5)
                .foregroundStyle(result.isEmpty ? .secondary : .primary).textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange) }
            if completed {
                HStack {
                    Button("复制英文", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string)
                    }
                    Spacer()
                    if let latency {
                        Text(latencyDescription(latency)).font(.caption).foregroundStyle(.secondary)
                            .help("发出服务请求后的耗时，不包含选词、本地等待和首次授权准备。")
                    }
                }
            }
        }
        Text("点击翻译后，仅将上面的文字发送至 OpenAI。试写内容不会被 Monkey 保存为历史记录。")
            .font(.caption).foregroundStyle(.secondary)
            .onDisappear { translationTask?.cancel() }
    }
    private func translate() {
        let submitted = draft
        isTranslating = true; completed = false; result = ""; errorMessage = nil; latency = nil
        translationTask = Task { @MainActor in
            defer { isTranslating = false }
            do {
                result = try await client.translate(submitted) { result += $0 }
                latency = client.lastTranslationLatency
                completed = true
            } catch {
                completed = false
                result = ""
                errorMessage = ChatGPTClient.userMessage(error)
            }
        }
    }

    private func latencyDescription(_ latency: TranslationLatency) -> String {
        let completed = String(format: "%.1f 秒", latency.completionMilliseconds / 1000)
        guard let firstToken = latency.firstTokenMilliseconds else { return "本次服务请求：完成 \(completed)" }
        return "本次服务请求：首段 \(String(format: "%.1f 秒", firstToken / 1000)) · 完成 \(completed)"
    }
}

private struct PrivacyPane: View {
    var body: some View {
        SettingsCard("哪些内容会联网") {
            Label("普通拼音、候选词和个人词库在本机处理。", systemImage: "internaldrive")
            Label("翻译模式只发送当前草稿；不自动读取整个文档或剪贴板。", systemImage: "character.bubble")
            Label("ChatGPT 凭据存入 macOS 钥匙串，不写入源码或诊断日志。", systemImage: "key")
            Label("Monkey 不保存翻译历史。请求使用 store: false；这不代表服务端零保留。", systemImage: "lock.shield")
        }.font(.callout)
        SettingsCard("常用操作") {
            shortcut("切换中文 / 中译英", "⌃⇧T")
            shortcut("切换中文 / 英文输入", "⇧ Space")
            shortcut("拼音选词", "空格 / 数字")
            shortcut("普通模式：原样输入拼音 / 英文", "Return")
            shortcut("候选翻页", "PgUp / PgDn / - / =")
            shortcut("确认英文并写入输入框", "⌃ Return")
            shortcut("翻译模式：直接输入中文草稿", "Return / ⇧ Return")
            shortcut("清除当前拼音 / 取消预览、保留中文", "Esc")
            Text("正在处理拼音或草稿时，确认键由 Monkey 消费；没有组合内容时，Return 仍由当前应用处理。英文尚未完成时，不会提交过期译文。")
                .font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard("开源与反馈") {
            Text("首版需要在你的常用应用中实际试用。遇到候选窗、混输或翻译问题，请提供应用名称和可复现步骤，避免提交密码、私密原文或登录凭据。")
                .font(.callout).foregroundStyle(.secondary)
            Link("打开 GitHub 仓库 ↗", destination: URL(string: "https://github.com/jiaqianjing/monkey")!)
        }
    }
    private func shortcut(_ text: String, _ keys: String) -> some View {
        HStack { Text(text).font(.callout); Spacer(); Text(keys).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary) }
    }
}
