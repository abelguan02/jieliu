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
        ScrollView {
        VStack(alignment:.leading,spacing:22) {
            HStack(spacing:14) {
                Image(systemName:"viewfinder").font(.system(size:32,weight:.light)).foregroundStyle(.cyan)
                VStack(alignment:.leading,spacing:4) {
                    Text(model.text("截留","Jieliu")).font(.system(size:28,weight:.semibold))
                    if onboarding { Text(model.text("截下的每一张，都有落点。","A home for every screenshot.")).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.3").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(model.text("语言","Language")).font(.headline)
                Spacer()
                Picker(model.text("语言","Language"),selection:$model.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                }.labelsHidden().frame(width:190)
            }
            if onboarding {
                VStack(alignment:.leading,spacing:10) {
                    Label(model.text("继续使用 ⌘⇧3、⌘⇧4 或 ⌘⇧5 截图","Keep capturing with ⌘⇧3, ⌘⇧4 or ⌘⇧5"),systemImage:"keyboard")
                    Label(model.text("新截图自动归档，顶部保留最近 8 张","New screenshots are archived; the tray keeps the latest 8"),systemImage:"tray.and.arrow.down")
                    Label(model.text("拖入其他 App 即可拷贝；移出托盘保留文件","Drag to other apps to copy; removing keeps the file"),systemImage:"hand.draw")
                }.font(.system(size:13))
                Text(model.text("首次监听桌面时，macOS 可能询问文件夹访问权限，请允许。只处理启用之后生成的截图，不搬动旧文件。","Allow folder access when macOS asks. Only new screenshots are collected; existing files stay where they are.")).font(.system(size:12)).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:10) {
                Text(model.text("收起入口","Collapsed entry")).font(.headline)
                Picker(model.text("收起入口","Collapsed entry"),selection:$model.entry) {
                    Text(model.text("取景框胶囊","Viewfinder capsule")).tag(TrayEntry.capsule)
                    Text(model.text("仅菜单栏图标","Menu bar icon only")).tag(TrayEntry.menuBarOnly)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:.infinity)
            }
            VStack(alignment:.leading,spacing:10) {
                Text(model.text("展开样式","Expanded style")).font(.headline)
                Picker(model.text("展开样式","Expanded style"),selection:$model.concept) {
                    ForEach(Concept.allCases) { concept in Text("\(concept.rawValue)  \(model.title(concept))").tag(concept) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:.infinity)
            }
            VStack(alignment:.leading,spacing:8) {
                Text(model.text("截图归档文件夹","Screenshot folder")).font(.headline)
                HStack {
                    Text(model.folderLabel).font(.system(size:12,design:.monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(model.text("更改…","Change…")) { model.chooseDestination() }
                    Button(model.text("打开","Open")) { model.openFolder() }
                }
            }
            Toggle(model.text("鼠标离开后自动收起","Collapse when the pointer leaves"),isOn:$model.autoHide)
                .disabled(model.entry == .menuBarOnly)
            Toggle(model.text("收纳音效","Capture sounds"),isOn:$model.sound)
            Toggle(model.text("界面动效","Interface animations"),isOn:$model.animations)
            Toggle(model.text("登录时启动","Launch at login"),isOn:$state.launchAtLogin).onChange(of:state.launchAtLogin) { _, enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { state.localError=model.text("登录启动设置失败：","Could not update launch at login: ")+error.localizedDescription; state.launchAtLogin=SMAppService.mainApp.status == .enabled }
            }
            if !model.lastError.isEmpty || !state.localError.isEmpty {
                Text(state.localError.isEmpty ? model.lastError : state.localError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                Button(model.text("重新请求目录访问并重试","Allow folder access and retry")) {
                    let panel=NSOpenPanel(); panel.canChooseFiles=false; panel.canChooseDirectories=true; panel.directoryURL=URL(fileURLWithPath:NSHomeDirectory()+"/Desktop"); panel.message=model.text("请选择系统截图保存目录（通常为桌面），允许截留读取新截图。","Choose your system screenshot folder (usually Desktop) to allow access to new screenshots.")
                    if panel.runModal() == .OK { model.lastError=""; model.onRestart?() }
                }
            }
            if onboarding { HStack { Spacer(); Button(model.text("开始收纳","Start collecting"),action:start).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) } }
        }.padding(28).frame(width:560).preferredColorScheme(.dark)
            .environment(\.locale,Locale(identifier:model.language.rawValue))
        }.frame(width:560,height:min(onboarding ? 740 : 560,(NSScreen.main?.visibleFrame.height ?? 900)-100))
            .preferredColorScheme(.dark)
    }
}
