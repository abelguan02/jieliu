import SwiftUI

final class OnboardingFlow:ObservableObject {
    @Published var page:Int
    init(page:Int) { self.page=page }
}

struct OnboardingView:View {
    @ObservedObject var model:AppModel
    var start:()->Void
    @StateObject private var state=SettingsState()
    @StateObject private var flow:OnboardingFlow
    private var page:Int { flow.page }
    init(model:AppModel,page:Int=0,start:@escaping ()->Void) {
        self.model=model; self.start=start; _flow=StateObject(wrappedValue:OnboardingFlow(page:page))
    }
    var body:some View {
        VStack(spacing:24) {
            Group {
                switch page {
                case 0: welcome
                case 1: usage
                default: setup
                }
            }.frame(maxWidth:.infinity,minHeight:300,maxHeight:300,alignment:.top)
            HStack(spacing:10) {
                HStack(spacing:6) {
                    ForEach(0..<3,id:\.self) { index in
                        Circle().fill(index == page ? Color.cyan : .white.opacity(0.2)).frame(width:6,height:6)
                    }
                }
                Spacer()
                if page>0 { Button(model.text("上一步","Back")) { flow.page -= 1 } }
                if page<2 {
                    Button(model.text("下一步","Continue")) { flow.page += 1 }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(model.text("开始收纳","Start collecting"),action:start).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(28).frame(width:520)
            .preferredColorScheme(.dark)
            .environment(\.locale,Locale(identifier:model.language.rawValue))
    }

    private var welcome:some View {
        VStack(spacing:14) {
            Image(nsImage:NSApp.applicationIconImage).resizable().frame(width:96,height:96).padding(.top,20)
            Text(model.text("欢迎使用截留","Welcome to Jieliu")).font(.system(size:26,weight:.semibold))
            Text(model.text("截下的每一张，都有落点。","A home for every screenshot.")).foregroundStyle(.secondary)
            Picker(model.text("语言","Language"),selection:$model.language) {
                ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
            }.pickerStyle(.segmented).labelsHidden().frame(width:200).padding(.top,14)
        }
    }

    private var usage:some View {
        VStack(alignment:.leading,spacing:24) {
            Text(model.text("怎么用","How it works")).font(.system(size:22,weight:.semibold))
            Step(symbol:"camera.viewfinder",title:model.text("照常截图","Capture as usual"),detail:"⌘⇧3 · ⌘⇧4 · ⌘⇧5")
            Step(symbol:"tray.and.arrow.down",title:model.text("自动收进顶部托盘","Collected at the top of the screen"),detail:model.text("托盘保留最近 8 张，原图归档到文件夹","The tray keeps the latest 8; originals are archived"))
            Step(symbol:"hand.draw",title:model.text("拖到其他 App 即可使用","Drag into any app"),detail:model.text("空格预览 · ⌘C 拷贝 · Delete 移出（文件保留）","Space preview · ⌘C copy · Delete removes (file kept)"))
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private var setup:some View {
        VStack(alignment:.leading,spacing:20) {
            Text(model.text("准备开始","Get ready")).font(.system(size:22,weight:.semibold))
            VStack(alignment:.leading,spacing:8) {
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
                }
            }
            Toggle(model.text("登录时启动","Launch at login"),isOn:Binding(get:{ state.launchAtLogin },set:{ state.setLaunchAtLogin($0,model) }))
            Label(model.text("在 ⌘⇧5 →「选项」中关闭「显示浮动缩略图」，截图会更快进入托盘。","Turn off Show Floating Thumbnail in ⌘⇧5 → Options for faster collection."),systemImage:"lightbulb")
                .font(.system(size:12)).foregroundStyle(.secondary)
            if !state.localError.isEmpty { Text(state.localError).font(.caption).foregroundStyle(.orange) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

private struct Step:View {
    let symbol:String, title:String, detail:String
    var body:some View {
        HStack(alignment:.top,spacing:14) {
            Image(systemName:symbol).font(.system(size:20)).foregroundStyle(.cyan).frame(width:28)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.system(size:14,weight:.medium))
                Text(detail).font(.system(size:12)).foregroundStyle(.secondary)
            }
        }
    }
}
