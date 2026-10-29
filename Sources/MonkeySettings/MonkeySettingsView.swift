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
            SettingsSidebar(selection: $selection, client: client)
            Rectangle().fill(SettingsPalette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeading(section: selection)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selection {
                        case .start:
                            StartPane(isConnected: client.accountEmail != nil,
                                      onConnect: { selection = .account },
                                      onTryTranslation: { selection = .translation },
                                      onTyping: { selection = .typing })
                        case .typing: TypingPane()
                        case .account: AccountPane(client: client)
                        case .translation: TranslationPane(client: client, onConnect: { selection = .account })
                        case .privacy: PrivacyPane()
                        }
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(selection)
            }
            .background(SettingsPalette.canvas)
        }
        .tint(SettingsPalette.action)
        .foregroundStyle(SettingsPalette.ink)
        .frame(minWidth: 860, idealWidth: 940, minHeight: 640, idealHeight: 720)
        .onAppear { client.reloadAccount() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: ChatGPTClient.accountChangedNotification)) { _ in client.reloadAccount() }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case start, typing, translation, account, privacy
    var id: Self { self }
    var title: String {
        switch self {
        case .start: return "概览"
        case .typing: return "中文输入"
        case .translation: return "中译英"
        case .account: return "账号连接"
        case .privacy: return "隐私与快捷键"
        }
    }
    var icon: String {
        switch self {
        case .start: return "square.grid.2x2"
        case .typing: return "keyboard"
        case .translation: return "character.bubble"
        case .account: return "person.crop.circle"
        case .privacy: return "lock.shield"
        }
    }
    var eyebrow: String {
        switch self {
        case .start: return "YOUR WORKSPACE"
        case .typing: return "TYPE YOUR WAY"
        case .translation: return "CHINESE IN. ENGLISH OUT."
        case .account: return "YOUR CONNECTION"
        case .privacy: return "STAY IN CONTROL"
        }
    }
    var heading: String {
        switch self {
        case .start: return "顺手输入，自在表达。"
        case .typing: return "把输入调成你的习惯。"
        case .translation: return "用中文想，用英文写。"
        case .account: return "带上你的 ChatGPT。"
        case .privacy: return "你的文字，你做主。"
        }
    }
    var subtitle: String {
        switch self {
        case .start: return "本地拼音与中译英，在指尖接上你的想法。"
        case .typing: return "候选、混输与空格，每个细节都顺手。"
        case .translation: return "先试写一句，再回到你正在使用的应用。"
        case .account: return "通过官方登录，连接账号可用的订阅额度。"
        case .privacy: return "清楚知道什么留在本机、什么会发送。"
        }
    }
}

private enum SettingsPalette {
    static let canvas = adaptive(light: 0xF5F5F0, dark: 0x141622)
    static let sidebar = adaptive(light: 0xECEEE7, dark: 0x10121C)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1E2131)
    static let inset = adaptive(light: 0xF3F4EF, dark: 0x171A28)
    static let ink = adaptive(light: 0x171B2E, dark: 0xF1F3ED)
    static let muted = adaptive(light: 0x606878, dark: 0xA3AABD)
    static let line = adaptive(light: 0xDDE2D8, dark: 0x34394A)
    static let action = adaptive(light: 0x171B2E, dark: 0xD7F879)
    static let onAction = adaptive(light: 0xFAFBF6, dark: 0x171B2E)
    static let selected = adaptive(light: 0xDBEBAD, dark: 0x303C28)
    static let lime = Color(red: 215 / 255, green: 248 / 255, blue: 121 / 255)
    static let midnight = Color(red: 23 / 255, green: 27 / 255, blue: 46 / 255)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

@MainActor
private enum BrandAssets {
    static let icon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) } ?? NSImage(named: "AppIcon")
}

private struct BrandMark: View {
    let size: CGFloat
    var body: some View {
        Group {
            if let icon = BrandAssets.icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(SettingsPalette.lime)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SettingsPalette.midnight, in: RoundedRectangle(cornerRadius: size * 0.23))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Monkey 应用图标")
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    @ObservedObject var client: ChatGPTClient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monkey").font(.system(size: 23, weight: .bold, design: .rounded)).tracking(-0.7)
                    Text("盲 key · 输入自如").font(.system(size: 11)).foregroundStyle(SettingsPalette.muted)
                }
            }
            .padding(.bottom, 36)
            Text("偏好设置").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundStyle(SettingsPalette.muted).padding(.horizontal, 12).padding(.bottom, 12)
            VStack(spacing: 5) {
                ForEach(SettingsSection.allCases) { section in
                    Button { selection = section } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.icon).font(.system(size: 15, weight: selection == section ? .semibold : .regular))
                                .frame(width: 20)
                            Text(section.title).font(.system(size: 13, weight: selection == section ? .semibold : .regular))
                            Spacer(minLength: 0)
                            if selection == section {
                                Circle().fill(SettingsPalette.action).frame(width: 4, height: 4)
                            }
                        }
                        .foregroundStyle(selection == section ? SettingsPalette.ink : SettingsPalette.muted)
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .background(selection == section ? SettingsPalette.selected : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }
            Spacer(minLength: 24)
            Button { selection = .account } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: client.requiresKeychainAuthorization ? "key" : "person.crop.circle")
                        .font(.system(size: 17)).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(client.accountEmail == nil ? "连接 ChatGPT" : (client.requiresKeychainAuthorization ? "钥匙串待授权" : "连接已保存"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(client.accountEmail == nil ? "为英文表达接上灵感" : "翻译时验证账号授权")
                            .font(.system(size: 10)).foregroundStyle(SettingsPalette.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).padding(.top, 5)
                }
                .foregroundStyle(SettingsPalette.ink)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsPalette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 7) {
                Label("本地拼音 · 离线可用", systemImage: "internaldrive").font(.system(size: 10))
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")  /  OPEN SOURCE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.4)
            }
            .foregroundStyle(SettingsPalette.muted).padding(.top, 18).padding(.horizontal, 3)
        }
        .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 22)
        .frame(width: 224).frame(maxHeight: .infinity)
        .background(SettingsPalette.sidebar)
    }
}

private struct SettingsHeading: View {
    let section: SettingsSection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.eyebrow).font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5).foregroundStyle(SettingsPalette.muted)
            Text(section.heading).font(.system(size: 28, weight: .bold)).tracking(-0.6)
            Text(section.subtitle).font(.system(size: 12)).foregroundStyle(SettingsPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 22)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    private let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(SettingsPalette.line.opacity(0.75), lineWidth: 0.8))
    }
}

private struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var lime = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(isEnabled ? (lime ? SettingsPalette.midnight : SettingsPalette.onAction) : SettingsPalette.muted)
            .background(isEnabled ? (lime ? SettingsPalette.lime : SettingsPalette.action) : SettingsPalette.inset,
                        in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct SecondaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(isEnabled ? SettingsPalette.ink : SettingsPalette.muted)
            .background(SettingsPalette.inset.opacity(configuration.isPressed ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SettingsPalette.line, lineWidth: 0.8))
            .opacity(isEnabled ? 1 : 0.6)
    }
}

private struct StatusPill: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol).font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(SettingsPalette.inset, in: Capsule())
    }
}

private struct KeyboardKey: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(SettingsPalette.inset, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsPalette.line, lineWidth: 0.8))
    }
}

private struct NoteLine: View {
    let text: String
    var symbol = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).padding(.top, 1)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SettingsPalette.muted)
    }
}

private struct StartPane: View {
    let isConnected: Bool
    let onConnect: () -> Void
    let onTryTranslation: () -> Void
    let onTyping: () -> Void
    @State private var installationExpanded = false

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("THINK IN CHINESE.").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6).foregroundStyle(SettingsPalette.lime)
                Text("专注想法。\n顺手表达。")
                    .font(.system(size: 29, weight: .semibold)).tracking(-0.5).foregroundStyle(.white)
                Text("中文留在本机，英文随手开启。")
                    .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.68))
                HStack(spacing: 14) {
                    Button(isConnected ? "试译一句" : "连接 ChatGPT", systemImage: "arrow.up.right") {
                        if isConnected { onTryTranslation() } else { onConnect() }
                    }
                    .buttonStyle(PrimaryActionStyle(lime: true))
                    Button("输入偏好") { onTyping() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.86))
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                BrandMark(size: 100)
                Text("⌃ ⇧ T").font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettingsPalette.lime).padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.midnight, in: RoundedRectangle(cornerRadius: 18))

        HStack(spacing: 12) {
            FeatureTile(symbol: "keyboard", title: "中文输入", detail: "全拼 · 简拼 · 本机学习", action: onTyping)
            FeatureTile(symbol: "character.bubble", title: "中译英", detail: "中文草稿 · 英文预览", action: onTryTranslation)
        }
        SettingsCard("中译英，三步就好") {
            GuideStep(number: "01", title: "连接账号", detail: "通过 ChatGPT 登录一次；登录不会自动开启翻译。")
            GuideStep(number: "02", title: "输入时，点「中译英」", detail: "也可按 ⌃⇧T。选好中文，英文随后在候选窗预览。")
            GuideStep(number: "03", title: "回车中文，⌃↩ 英文", detail: "中文可直接提交；译文完成后，用 Control Return 确认英文。")
            NoteLine(text: "只有主动开启中译英后，当前草稿才会发送至 OpenAI。", symbol: "lock")
        }
        DisclosureGroup(isExpanded: $installationExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("在系统设置 → 键盘 → 文字输入 → 编辑中添加 Monkey，再从菜单栏选中。如果尚未出现，请注销 macOS 用户再登录。")
                    .font(.system(size: 12)).foregroundStyle(SettingsPalette.muted).fixedSize(horizontal: false, vertical: true)
                Button("打开键盘设置", systemImage: "gearshape") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
                .buttonStyle(SecondaryActionStyle())
            }.padding(.top, 12)
        } label: {
            Label("首次安装？添加 Monkey 输入源", systemImage: "keyboard.badge.ellipsis")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(16).background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FeatureTile: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 10)).foregroundStyle(SettingsPalette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium)).foregroundStyle(SettingsPalette.muted)
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(SettingsPalette.line.opacity(0.7), lineWidth: 0.8))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}

private struct GuideStep: View {
    let number: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettingsPalette.muted).frame(width: 24, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(SettingsPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PreferenceToggle: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16)).frame(width: 24, height: 24)
                    .foregroundStyle(SettingsPalette.muted)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(SettingsPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch).controlSize(.small)
    }
}

@MainActor
private struct TypingPane: View {
    @AppStorage("typing.automaticEnglish", store: TypingPreferences.defaults) private var automaticEnglish = true
    @AppStorage("typing.horizontalCandidates", store: TypingPreferences.defaults) private var horizontalCandidates = true
    @AppStorage("typing.englishSpaceInsertsSpace", store: TypingPreferences.defaults) private var englishSpaceInsertsSpace = true
    @State private var folderMessage: String?

    var body: some View {
        SettingsCard("候选与混输") {
            PreferenceToggle(title: "识别常见英文产品词", detail: "例如 macOS、GitHub。其他拼音或英文仍可按 Return 原样输入。", symbol: "textformat.abc", isOn: $automaticEnglish)
            Divider().overlay(SettingsPalette.line)
            PreferenceToggle(title: "横排候选", detail: "横向排列更紧凑；关闭后使用竖排。", symbol: "rectangle.split.3x1", isOn: $horizontalCandidates)
            Divider().overlay(SettingsPalette.line)
            PreferenceToggle(title: "英文空格保留分隔", detail: "Space 确认英文并附带空格；Return 原样确认，不加空格。", symbol: "space", isOn: $englishSpaceInsertsSpace)
        }
        HStack(spacing: 8) {
            KeyboardKey(text: "macOS 13")
            KeyboardKey(text: "hello world")
            Text("保留英文大小写、数字和 ASCII 符号。")
                .font(.system(size: 10)).foregroundStyle(SettingsPalette.muted)
        }
        .padding(.horizontal, 2)
        SettingsCard("越用，越顺手") {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "internaldrive").font(.system(size: 26)).foregroundStyle(SettingsPalette.muted)
                VStack(alignment: .leading, spacing: 7) {
                    Text("常用候选会根据本机选词逐渐学习。")
                        .font(.system(size: 13, weight: .medium))
                    Text("在候选窗口右键某个词，可清除该词的个人学习记录。基础词库仍保留，内置候选可能继续出现。")
                        .font(.system(size: 11)).foregroundStyle(SettingsPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("打开本机词库", systemImage: "folder") { openUserDictionary() }.buttonStyle(SecondaryActionStyle())
            if let folderMessage { NoteLine(text: folderMessage) }
            NoteLine(text: "只打开文件夹，不会清空或重置词库。", symbol: "lock")
        }
        SettingsCard("普通中文输入") {
            ShortcutRow(title: "选词", keys: "Space / 数字")
            ShortcutRow(title: "候选翻页", keys: "PgUp / PgDn / - / =")
            ShortcutRow(title: "原样输入当前拼音或英文", keys: "Return")
            ShortcutRow(title: "切换中文与英文直输", keys: "⇧ Space")
        }
    }

    private func openUserDictionary() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monkey/Rime", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            folderMessage = "词库会在首次使用 Monkey 拼音后建立。"
            return
        }
        folderMessage = NSWorkspace.shared.open(folder) ? nil : "暂时无法打开词库，请稍后重试。"
    }
}

@MainActor
private struct AccountPane: View {
    @ObservedObject var client: ChatGPTClient
    @State private var actionMessage: String?
    @State private var isWorking = false

    var body: some View {
        SettingsCard("ChatGPT 连接") {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle").font(.system(size: 33)).foregroundStyle(SettingsPalette.muted)
                VStack(alignment: .leading, spacing: 5) {
                    Text(client.accountEmail ?? "连接你的账号").font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
                    Text(client.accountEmail == nil ? "符合条件的订阅账号可授权使用额度。" : "已保存连接，翻译时验证授权与可用额度。")
                        .font(.system(size: 11)).foregroundStyle(SettingsPalette.muted)
                }
                Spacer(minLength: 0)
                if client.accountEmail != nil {
                    StatusPill(text: client.requiresKeychainAuthorization ? "待授权" : "已保存", symbol: client.requiresKeychainAuthorization ? "key" : "link")
                }
            }
            Text(actionMessage ?? client.statusMessage).font(.system(size: 12)).foregroundStyle(SettingsPalette.muted)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(client.isSigningIn ? "正在等待浏览器…" : "Continue with ChatGPT") { run { try await client.signIn() } }
                    .buttonStyle(PrimaryActionStyle()).disabled(isWorking || client.isSigningIn)
                if client.isSigningIn {
                    Button("取消") { client.cancelSignIn() }.buttonStyle(SecondaryActionStyle())
                }
                if client.accountEmail != nil {
                    Button("退出登录") { run { try await client.signOut() } }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SettingsPalette.muted).disabled(isWorking)
                }
                if isWorking { ProgressView().controlSize(.small) }
            }
            NoteLine(text: "需要账号符合订阅使用条件；登录不会授权读取 ChatGPT 聊天记录。", symbol: "lock")
        }
        if client.activeAccountID != nil && !client.accounts.isEmpty {
            SettingsCard("钥匙串授权") {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "key.horizontal").font(.system(size: 23)).foregroundStyle(SettingsPalette.muted)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(client.requiresKeychainAuthorization ? "需要一次系统授权" : "凭据由 macOS 保管")
                            .font(.system(size: 13, weight: .semibold))
                        Text(client.requiresKeychainAuthorization ? "点击下方按钮后，请亲自处理 macOS 的授权提示。" : "首次使用或应用更新后，系统可能要求重新允许访问。你可以在这里主动重试。")
                            .font(.system(size: 11)).foregroundStyle(SettingsPalette.muted).fixedSize(horizontal: false, vertical: true)
                        Button("允许钥匙串访问", systemImage: "key") { run { try await client.authorizeKeychainAccess() } }
                            .buttonStyle(SecondaryActionStyle()).disabled(isWorking || client.isSigningIn)
                    }
                }
            }
        }
        SettingsCard("翻译模型") {
            if client.models.isEmpty {
                Text("从当前账号获取可用模型。列表中的模型也可能受到资格与额度限制。")
                    .font(.system(size: 12)).foregroundStyle(SettingsPalette.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("选择模型", selection: $client.selectedModel) {
                    ForEach(client.models) { model in Text(model.displayName).tag(model.slug) }
                }
                .font(.system(size: 12))
            }
            HStack {
                Button("刷新可用模型", systemImage: "arrow.clockwise") { run { try await client.refreshModels() } }
                    .buttonStyle(SecondaryActionStyle()).disabled(client.accountEmail == nil || isWorking)
                Spacer()
                Link("管理用量与授权 ↗", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                    .font(.system(size: 11))
            }
        }
        if !client.accounts.isEmpty {
            SettingsCard("已保存的连接") {
                ForEach(client.accounts) { account in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.email).font(.system(size: 12, weight: .medium))
                            Text("连接 \(String(account.clientID.suffix(8)))").font(.system(size: 10, design: .monospaced)).foregroundStyle(SettingsPalette.muted)
                        }
                        Spacer()
                        if client.activeAccountID == account.clientID {
                            StatusPill(text: "当前连接", symbol: "link")
                        } else {
                            Button("选择") { client.selectAccount(account.clientID) }.buttonStyle(SecondaryActionStyle()).disabled(isWorking)
                        }
                    }
                }
                Button("添加其他账号或工作区", systemImage: "plus") { run { try await client.signIn(asNewAccount: true) } }
                    .buttonStyle(SecondaryActionStyle()).disabled(isWorking)
            }
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
    let onConnect: () -> Void
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
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard("中文草稿") {
                TextEditor(text: $draft).font(.system(size: 14)).lineSpacing(4)
                    .scrollContentBackground(.hidden).frame(height: 92).padding(10)
                    .background(SettingsPalette.inset, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SettingsPalette.line, lineWidth: 0.8))
                    .accessibilityLabel("待翻译中文草稿")
                HStack(spacing: 16) {
                    Picker("表达语气", selection: $tone) {
                        Text("自然日常").tag("natural")
                        Text("简洁商务").tag("business")
                    }
                    .font(.system(size: 12)).frame(maxWidth: 260).disabled(isTranslating)
                    Spacer(minLength: 0)
                    Toggle("响应优先", isOn: $preferSpeed).toggleStyle(.switch).controlSize(.small)
                        .font(.system(size: 11)).fixedSize().disabled(isTranslating)
                }
                HStack(alignment: .center, spacing: 14) {
                    Text(speedExplanation).font(.system(size: 10)).foregroundStyle(SettingsPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isTranslating {
                        ProgressView().controlSize(.small)
                        Button("取消") { translationTask?.cancel() }.buttonStyle(SecondaryActionStyle())
                    } else {
                        Button("翻译为英文", systemImage: "arrow.down.right") { translate() }
                            .buttonStyle(PrimaryActionStyle())
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || client.accountEmail == nil)
                    }
                }
                if client.accountEmail == nil || client.requiresKeychainAuthorization {
                    HStack(spacing: 12) {
                        NoteLine(text: client.accountEmail == nil ? "先连接 ChatGPT，草稿会留在这里。" : "账号需要钥匙串授权，草稿会留在这里。", symbol: "key")
                        Spacer(minLength: 0)
                        Button(client.accountEmail == nil ? "连接账号" : "去授权") { onConnect() }
                            .buttonStyle(SecondaryActionStyle())
                    }
                }
            }
            SettingsCard(completed ? "英文译文" : "英文预览") {
                Text(result.isEmpty ? (isTranslating ? "正在组织英文表达…" : "译文会出现在这里。") : result)
                    .font(.system(size: 15)).lineSpacing(5)
                    .foregroundStyle(result.isEmpty ? SettingsPalette.muted : SettingsPalette.ink).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if completed {
                    HStack(alignment: .center, spacing: 12) {
                        Button("复制英文", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string)
                        }
                        .buttonStyle(SecondaryActionStyle())
                        Spacer(minLength: 0)
                        if let latency {
                            Text(latencyDescription(latency)).font(.system(size: 10)).foregroundStyle(SettingsPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .help("发出服务请求后的耗时，不包含选词、本地等待和首次授权准备。")
                        }
                    }
                }
            }
            NoteLine(text: "点击翻译后，仅将上面的文字发送至 OpenAI。Monkey 不保存试写历史。", symbol: "lock")
        }
        .onDisappear { translationTask?.cancel() }
    }

    private var speedExplanation: String {
        if TranslationRequestPolicy.reasoningEffort(model: client.selectedModel, preferSpeed: true) == nil {
            return "当前模型使用默认响应设置；响应优先目前支持 GPT-6.1 Terra。"
        }
        return "日常翻译优先更快显示，仍使用你选择的模型；关闭后使用模型默认设置。"
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
        SettingsCard("输入与隐私的边界") {
            PrivacyRow(symbol: "internaldrive", title: "中文输入，留在本机", detail: "拼音、候选排序和个人词库在本地处理。")
            Divider().overlay(SettingsPalette.line)
            PrivacyRow(symbol: "character.bubble", title: "只翻译你当前的草稿", detail: "主动开启中译英后才发送；不自动读取整个文档或剪贴板。")
            Divider().overlay(SettingsPalette.line)
            PrivacyRow(symbol: "key", title: "登录凭据，由系统保护", detail: "凭据存入 macOS 钥匙串，不写入源码或诊断日志。")
            Divider().overlay(SettingsPalette.line)
            PrivacyRow(symbol: "clock.arrow.circlepath", title: "不保存翻译历史", detail: "请求不保存响应；这不代表服务端零保留，仍适用 OpenAI 的数据政策。")
        }
        SettingsCard("熟悉这几个键，就够了") {
            ShortcutRow(title: "开启或关闭中译英", keys: "⌃ ⇧ T")
            ShortcutRow(title: "切换中文与英文直输", keys: "⇧ Space")
            ShortcutRow(title: "拼音选词", keys: "Space / 数字")
            ShortcutRow(title: "普通模式：原样输入拼音或英文", keys: "Return")
            ShortcutRow(title: "候选翻页", keys: "PgUp / PgDn / - / =")
            ShortcutRow(title: "翻译模式：提交中文", keys: "Return / ⇧ Return")
            ShortcutRow(title: "确认已完成的英文", keys: "⌃ Return")
            ShortcutRow(title: "清除拼音或取消预览，保留草稿", keys: "Esc")
            NoteLine(text: "没有组合内容时，Return 交给当前应用。英文未完成时，不会提交过期译文。")
        }
        HStack {
            NoteLine(text: "欢迎反馈可公开的复现示例，请勿包含密码或私人内容。", symbol: "bubble.left")
            Spacer(minLength: 0)
            Link("GitHub ↗", destination: URL(string: "https://github.com/jiaqianjing/monkey")!).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 2)
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(SettingsPalette.muted).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(SettingsPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let keys: String
    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 12))
            Spacer(minLength: 0)
            KeyboardKey(text: keys)
        }
    }
}
