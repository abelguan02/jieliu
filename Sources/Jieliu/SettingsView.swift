import SwiftUI
import ServiceManagement

final class SettingsState:ObservableObject {
    @Published var launchAtLogin=SMAppService.mainApp.status == .enabled
    @Published var localError=""
}

struct SettingsView:View {
    @ObservedObject var model:AppModel
    var onboarding:Bool
    var start:()->Void
    @ObservedObject private var state=SettingsState()
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(spacing:14) {
                Image(systemName:"viewfinder").font(.system(size:32,weight:.light)).foregroundStyle(.cyan)
                VStack(alignment:.leading,spacing:4) {
                    Text("截留").font(.system(size:28,weight:.semibold))
                    Text(onboarding ? "截下的每一张，都有落点。" : "截图的收纳托盘").foregroundStyle(.secondary)
                }
                Spacer()
                Text("1.0.0").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
            }
            Divider()
            if onboarding {
                VStack(alignment:.leading,spacing:10) {
                    Label("继续使用 ⌘⇧3、⌘⇧4 或 ⌘⇧5 截图",systemImage:"keyboard")
                    Label("新截图自动归档，顶部保留最近 8 张",systemImage:"tray.and.arrow.down")
                    Label("拖入其他 App 即可拷贝；移出托盘保留文件",systemImage:"hand.draw")
                }.font(.system(size:13))
                Text("首次监听桌面时，macOS 可能询问文件夹访问权限，请允许。只处理启用之后生成的截图，不搬动旧文件。").font(.system(size:12)).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:10) {
                Text("视觉方案").font(.headline)
                Picker("视觉方案",selection:$model.concept) {
                    ForEach(Concept.allCases) { concept in Text("\(concept.rawValue)  \(concept.title)").tag(concept) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment:.leading,spacing:8) {
                Text("截图归档文件夹").font(.headline)
                HStack {
                    Text(model.folderLabel).font(.system(size:12,design:.monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("更改…") { model.chooseDestination() }
                    Button("打开") { model.openFolder() }
                }
                Text("更改目录仅影响后续截图，现有文件留在原处。").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("鼠标离开后自动收起",isOn:$model.autoHide)
            Toggle("收纳音效",isOn:$model.sound)
            Toggle("登录时启动",isOn:$state.launchAtLogin).onChange(of:state.launchAtLogin) { _, enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { state.localError="登录启动设置失败：\(error.localizedDescription)"; state.launchAtLogin=SMAppService.mainApp.status == .enabled }
            }
            VStack(alignment:.leading,spacing:8) {
                Text("让截图更快进入托盘").font(.headline)
                Text("按 ⌘⇧5 →「选项」，关闭「显示浮动缩略图」。保持开启时，截留需等待系统写入文件后才能接收。").font(.system(size:12)).foregroundStyle(.secondary)
                Text("空格 / 双击预览 · ⇧ / ⌘ 多选 · Delete 移出 · ⌘C 拷贝").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
            }.padding(14).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
            if !model.lastError.isEmpty || !state.localError.isEmpty {
                Text(state.localError.isEmpty ? model.lastError : state.localError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                Button("重新请求目录访问并重试") {
                    let panel=NSOpenPanel(); panel.canChooseFiles=false; panel.canChooseDirectories=true; panel.directoryURL=URL(fileURLWithPath:NSHomeDirectory()+"/Desktop"); panel.message="请选择系统截图保存目录（通常为桌面），允许截留读取新截图。"
                    if panel.runModal() == .OK { model.lastError=""; model.onRestart?() }
                }
            }
            if onboarding { HStack { Spacer(); Button("开始收纳",action:start).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) } }
        }.padding(28).frame(width:500).preferredColorScheme(.dark)
    }
}
