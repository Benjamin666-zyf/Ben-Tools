import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
struct BenPakeApp: App {
    var body: some Scene {
        Window("Ben-Pake", id: "builder") {
            BuildView()
                .frame(minWidth: 690, minHeight: 600)
        }
        .defaultSize(width: 760, height: 690)
    }
}

@MainActor
private final class BuildForm: ObservableObject {
    @Published var website = ""
    @Published var name = ""
    @Published var width = "1200"
    @Published var height = "780"
    @Published var icon: URL?
    @Published var selectedSite: GallerySite?
    @Published var category: GalleryCategory = .all
    @Published var section: Section = .gallery
    @Published var options = WebsiteOptions()
    @Published var styles = ""
    @Published var script = ""
    @Published var advanced = false

    enum Section { case gallery, settings }

    func select(_ site: GallerySite) {
        selectedSite = site
        icon = nil
        website = site.url
        name = site.title
        section = .settings
    }

    @Published var directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)
    @Published var status: Status = .ready
    @Published var logs: [String] = []

    enum Status {
        case ready, building, success(URL), failure(String)

        var isBuilding: Bool {
            if case .building = self { return true }
            return false
        }
    }

}

private struct BuildView: View {
    @StateObject private var form = BuildForm()

    private let catalog = GallerySite.load()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                if form.section == .gallery {
                    gallery
                } else {
                    settings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.09, green: 0.13, blue: 0.16))
        }
        .preferredColorScheme(.dark)
        .tint(.mint)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ben-Pake", systemImage: "shippingbox")
                .font(.headline)
                .foregroundStyle(.mint)
                .padding(.bottom, 14)
            sidebarButton("网站精选", icon: "square.grid.2x2", section: .gallery)
            sidebarButton("打包设置", icon: "slider.horizontal.3", section: .settings)
            Spacer()
            Link(destination: URL(string: "https://github.com/Benjamin666-zyf/Ben-Tools/actions/workflows/pake-cli.yaml")!) {
                Label("Windows 打包", systemImage: "arrow.up.right")
                    .font(.callout)
            }
        }
        .buttonStyle(.plain)
        .padding(18)
        .frame(width: 155, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.10, blue: 0.13))
    }

    private func sidebarButton(_ title: String, icon: String, section: BuildForm.Section) -> some View {
        Button {
            form.section = section
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(form.section == section ? Color.mint.opacity(0.17) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityAddTraits(form.section == section ? .isSelected : [])
    }

    private var visibleSites: [GallerySite] {
        let query = form.website.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.filter { site in
            (form.category == .all || site.category == form.category.rawValue)
            && (query.isEmpty || site.title.localizedCaseInsensitiveContains(query)
                || site.url.localizedCaseInsensitiveContains(query))
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("选择要打包的网站").font(.title.bold()).accessibilityAddTraits(.isHeader)
            HStack {
                TextField("网站网址或名称", text: $form.website, prompt: Text("粘贴网址或搜索网站"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(openWebsite)
                Button("使用网址", action: openWebsite)
                    .buttonStyle(.borderedProminent)
                    .disabled(form.website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || form.status.isBuilding)
            }
            Picker("分类", selection: $form.category) {
                ForEach(GalleryCategory.allCases) { category in Text(category.title).tag(category) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                if visibleSites.isEmpty {
                    Text("没有匹配网站").foregroundStyle(.secondary).padding(.vertical, 30)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 12)], spacing: 12) {
                    ForEach(visibleSites) { site in
                        Button {
                            form.select(site)
                        } label: {
                            VStack(spacing: 8) {
                                siteMark(site, size: 34)
                                Text(site.title).font(.caption.weight(.medium)).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .padding(.horizontal, 6)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(form.status.isBuilding)
                    }
                }
            }
        }
        .padding(24)
    }

    private func openWebsite() {
        guard !form.website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !form.status.isBuilding else { return }
        if let site = form.selectedSite, site.url != form.website {
            form.selectedSite = nil
            form.icon = nil
            form.name = ""
        }
        if form.name.isEmpty {
            form.name = URLComponents(string: form.website)?.host ?? ""
        }
        form.section = .settings
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                siteMark(form.selectedSite, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(form.name.isEmpty ? "打包设置" : form.name).font(.title2.bold()).lineLimit(1)
                    Text("macOS 磁盘映像").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: start) {
                    if case .failure = form.status { Text("重试打包") }
                    else { Text("生成 DMG") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(form.status.isBuilding)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    card("基本信息") {
                        TextField("网站网址", text: $form.website, prompt: Text("https://example.com"))
                        TextField("应用名称", text: $form.name)
                        LabeledContent("图标") {
                            HStack {
                                Text(form.icon?.lastPathComponent ?? "来自网站").lineLimit(1).foregroundStyle(.secondary)
                                Button("选择…", action: chooseIcon).accessibilityLabel("选择图标")
                                if form.icon != nil { Button("移除") { form.icon = nil } }
                            }
                        }
                        LabeledContent("保存位置") {
                            HStack {
                                Text(form.directory.path.abbreviatingHome).lineLimit(1).truncationMode(.middle)
                                Button("选择…", action: chooseDirectory).accessibilityLabel("选择保存位置")
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    card("窗口") {
                        LabeledContent("默认尺寸") {
                            HStack {
                                TextField("宽度", text: $form.width).labelsHidden().frame(width: 64)
                                Text("×").accessibilityHidden(true)
                                TextField("高度", text: $form.height).labelsHidden().frame(width: 64)
                            }
                            .textFieldStyle(.roundedBorder)
                        }
                        option("全屏启动", $form.options.fullscreen)
                        option("隐藏标题栏", $form.options.hideTitleBar)
                        option("深色窗口", $form.options.darkMode)
                        option("关闭窗口后在后台运行", $form.options.hideOnClose)
                        option("显示菜单栏图标", $form.options.showSystemTray)
                    }
                    card("高级") {
                        DisclosureGroup("导航、浏览、代理与注入", isExpanded: $form.advanced) {
                            VStack(alignment: .leading, spacing: 12) {
                                option("打开时恢复上次页面", $form.options.restoreLastUrl)
                                option("支持多个窗口", $form.options.multiWindow)
                                option("新链接在应用窗口打开", $form.options.newWindow)
                                option("窗口始终置顶", $form.options.alwaysOnTop)
                                option("无痕浏览", $form.options.incognito)
                                option("启动时只显示菜单栏图标", $form.options.startToTray)
                                    .disabled(!form.options.showSystemTray)
                                TextField("全局快捷键", text: $form.options.activationShortcut)
                                TextField("代理", text: $form.options.proxyUrl)
                                TextField("User Agent", text: $form.options.userAgent)
                                codeEditor("注入 CSS", text: $form.styles)
                                codeEditor("注入 JavaScript", text: $form.script)
                            }
                            .padding(.top, 10)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .disabled(form.status.isBuilding)
            }
            statusView
            if !form.logs.isEmpty { buildLog }
        }
        .padding(24)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.headline).foregroundStyle(.mint).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func option(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func codeEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 85)
                .accessibilityLabel(title)
        }
    }

    private var buildLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(form.logs.indices, id: \.self) { index in
                        Text(form.logs[index]).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
            }
            .frame(height: 105)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("打包日志")
            .onChange(of: form.logs.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private func siteMark(_ site: GallerySite?, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.mint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                if let site {
                    Text(String(site.title.prefix(1))).font(.headline).foregroundStyle(.mint)
                } else {
                    Image(systemName: "globe").foregroundStyle(.mint)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var statusView: some View {
        switch form.status {
        case .ready:
            Text("准备打包").foregroundStyle(.secondary)
        case .building:
            HStack {
                ProgressView().controlSize(.small)
                Text("正在打包…")
            }
        case .success(let file):
            HStack {
                Label(file.lastPathComponent, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("在 Finder 中查看") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
            }
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns, .svg, .webP, .gif]
        if panel.runModal() == .OK { form.icon = panel.url }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = form.directory
        if panel.runModal() == .OK, let selection = panel.url { form.directory = selection }
    }

    private func start() {
        guard !form.status.isBuilding else { return }
        form.logs = []
        do {
            var options = form.options
            if !options.showSystemTray { options.startToTray = false }
            let motif = form.selectedSite.flatMap { $0.url == form.website ? $0.icon : nil }
            let recipe = try Recipe(url: form.website, name: form.name, icon: form.icon,
                                    width: form.width, height: form.height, options: options,
                                    styles: form.styles, script: form.script, galleryIcon: motif)
            guard let resources = Bundle.main.resourceURL else {
                throw BuildFailure("无法读取 Ben-Pake 的应用资源。")
            }
            let builder = Builder(cli: resources.appendingPathComponent("pake/dist/cli.js"))
            let model = form
            let folder = model.directory
            form.status = .building
            Task {
                do {
                    let file = try await Task.detached {
                        try builder.build(recipe, in: folder) { line in
                            DispatchQueue.main.async { model.logs.append(line) }
                        }
                    }.value
                    form.status = .success(file)
                } catch {
                    form.status = .failure(error.localizedDescription)
                }
            }
        } catch {
            form.status = .failure(error.localizedDescription)
        }
    }
}

private extension String {
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}

private struct GallerySite: Decodable, Identifiable {
    let id: String
    let name: [String: String]
    let url: String
    let category: String
    let icon: String?

    var title: String { name["zh-Hans"] ?? name["en"] ?? id }

    static func load() -> [GallerySite] {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("gallery"),
              let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        return contents.compactMap { file -> GallerySite? in
            guard file.pathExtension == "json", let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(Self.self, from: data)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

private enum GalleryCategory: String, CaseIterable, Identifiable {
    case all, ai, productivity, social, media, reading, developer

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部"
        case .ai: "AI"
        case .productivity: "效率"
        case .social: "社交"
        case .media: "影音"
        case .reading: "阅读"
        case .developer: "开发"
        }
    }
}
