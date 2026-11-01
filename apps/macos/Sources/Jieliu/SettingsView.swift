import SwiftUI
import ServiceManagement

final class SettingsState:ObservableObject {
    @Published var launchAtLogin=SMAppService.mainApp.status == .enabled
    @Published var localError=""
    func setLaunchAtLogin(_ enabled:Bool,_ model:AppModel) {
        launchAtLogin=enabled
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { localError=model.text("登录启动设置失败：","Could not update launch at login: ")+error.localizedDescription; launchAtLogin=SMAppService.mainApp.status == .enabled }
    }
}

struct SettingsView:View {
    @ObservedObject var model:AppModel
    var about:()->Void
    @StateObject private var state=SettingsState()
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack {
                Text(model.text("语言","Language")).font(.headline)
                Spacer()
                Picker(model.text("语言","Language"),selection:$model.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                }.labelsHidden().frame(width:190)
            }
            VStack(alignment:.leading,spacing:10) {
                Text(model.text("收起入口","Collapsed entry")).font(.headline)
                Picker(model.text("收起入口","Collapsed entry"),selection:$model.entry) {
                    Text(model.text("取景框胶囊","Viewfinder capsule")).tag(TrayEntry.capsule)
                    Text(model.text("仅菜单栏图标","Menu bar icon only")).tag(TrayEntry.menuBarOnly)
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment:.leading,spacing:10) {
                Text(model.text("展开样式","Expanded style")).font(.headline)
                Picker(model.text("展开样式","Expanded style"),selection:$model.concept) {
                    ForEach(Concept.allCases) { concept in Text("\(concept.rawValue)  \(model.title(concept))").tag(concept) }
                }.pickerStyle(.segmented).labelsHidden()
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
            VStack(alignment:.leading,spacing:12) {
                Toggle(model.text("鼠标离开后自动收起","Collapse when the pointer leaves"),isOn:$model.autoHide)
                    .disabled(model.entry == .menuBarOnly)
                Toggle(model.text("收纳音效","Capture sounds"),isOn:$model.sound)
                Toggle(model.text("界面动效","Interface animations"),isOn:$model.animations)
                Toggle(model.text("登录时启动","Launch at login"),isOn:Binding(get:{ state.launchAtLogin },set:{ state.setLaunchAtLogin($0,model) }))
            }
            if !model.lastError.isEmpty || !state.localError.isEmpty {
                Text(state.localError.isEmpty ? model.lastError : state.localError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                Button(model.text("重新请求目录访问并重试","Allow folder access and retry")) {
                    let panel=NSOpenPanel(); panel.canChooseFiles=false; panel.canChooseDirectories=true; panel.directoryURL=URL(fileURLWithPath:NSHomeDirectory()+"/Desktop"); panel.message=model.text("请选择系统截图保存目录（通常为桌面），允许截留读取新截图。","Choose your system screenshot folder (usually Desktop) to allow access to new screenshots.")
                    if panel.runModal() == .OK { model.lastError=""; model.onRestart?() }
                }
            }
            Divider()
            Button(model.text("关于截留","About Jieliu"),action:about).buttonStyle(.link)
        }.padding(28).frame(width:500)
            .preferredColorScheme(.dark)
            .environment(\.locale,Locale(identifier:model.language.rawValue))
    }
}
