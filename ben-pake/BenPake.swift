import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
struct BenPakeApp: App {
    var body: some Scene {
        Window("Ben-Pake", id: "builder") {
            BuildView()
                .frame(minWidth: 570, minHeight: 570)
        }
        .defaultSize(width: 620, height: 620)
    }
}

@MainActor
private final class BuildForm: ObservableObject {
    @Published var website = ""
    @Published var name = ""
    @Published var width = "1200"
    @Published var height = "780"
    @Published var icon: URL?
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Label("网站打包", systemImage: "macwindow")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Link(destination: URL(string: "https://github.com/Benjamin666-zyf/Ben-Tools/actions/workflows/pake-cli.yaml")!) {
                    Label("Windows 打包", systemImage: "arrow.up.right")
                }
            }

            Form {
                TextField("网站网址", text: $form.website, prompt: Text("https://example.com"))
                TextField("应用名称", text: $form.name)
                LabeledContent("图标") {
                    HStack {
                        Text(form.icon?.lastPathComponent ?? "自动获取").lineLimit(1)
                            .foregroundStyle(.secondary)
                        Button("选择…") { chooseIcon() }.accessibilityLabel("选择图标")
                        if form.icon != nil { Button("移除") { form.icon = nil } }
                    }
                }
                LabeledContent("窗口尺寸") {
                    HStack {
                        TextField("宽度", text: $form.width)
                            .labelsHidden().frame(width: 68)
                        Text("×").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("高度", text: $form.height)
                            .labelsHidden().frame(width: 68)
                    }
                }
                LabeledContent("保存位置") {
                    HStack {
                        Text(form.directory.path(percentEncoded: false).abbreviatingHome)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("选择…") { chooseDirectory() }.accessibilityLabel("选择保存位置")
                    }
                }
            }
            .disabled(form.status.isBuilding)

            Divider()
            statusView
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
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("打包日志")
                .onChange(of: form.logs.last) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack {
                Spacer()
                Button(action: start) {
                    if case .failure = form.status {
                        Text("重试打包")
                    } else {
                        Text("生成 DMG")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(form.status.isBuilding)
            }
        }
        .padding(26)
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
            let recipe = try Recipe(url: form.website, name: form.name, icon: form.icon, width: form.width, height: form.height)
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
