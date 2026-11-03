import SwiftUI

enum AppInfo {
    static let repository=URL(string:"https://github.com/abelguan02/jieliu")!
    static let feedback=URL(string:"https://github.com/abelguan02/jieliu/issues/new")!
    /// Packaged resources first; command-line checks read the same files from the repository.
    static func resource(_ name:String,_ ext:String)->URL? {
        if let url=Bundle.main.url(forResource:name,withExtension:ext) { return url }
        let url=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("apps/macos/Resources/\(name).\(ext)")
        return FileManager.default.fileExists(atPath:url.path) ? url : nil
    }
    static var version:String {
        let bundled=Bundle.main.infoDictionary
        let info=bundled?["CFBundleShortVersionString"] != nil ? bundled : resource("Info","plist").flatMap { NSDictionary(contentsOf:$0) as? [String:Any] }
        let short=info?["CFBundleShortVersionString"] as? String ?? "—"
        return (info?["CFBundleVersion"] as? String).map { "\(short) (\($0))" } ?? short
    }
}

struct AboutView:View {
    @ObservedObject var model:AppModel
    var guide:()->Void
    var body:some View {
        VStack(spacing:20) {
            VStack(spacing:6) {
                Image(nsImage:NSApp.applicationIconImage).resizable().frame(width:72,height:72)
                Text(model.text("截留","Jieliu")).font(.system(size:22,weight:.semibold))
                Text(model.text("版本 ","Version ")+AppInfo.version).font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary)
            }
            VStack(spacing:0) {
                LinkRow(symbol:"chevron.left.forwardslash.chevron.right",title:model.text("开源仓库","Source code"),detail:"github.com/abelguan02/jieliu",url:AppInfo.repository)
                Divider().padding(.leading,42)
                LinkRow(symbol:"text.bubble",title:model.text("反馈与建议","Feedback"),detail:"GitHub Issues",url:AppInfo.feedback)
            }.background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
            VStack(spacing:12) {
                Text(model.text("自愿打赏","Support Jieliu")).font(.headline)
                HStack(spacing:24) {
                    DonationCode(name:"Donate-WeChat",title:model.text("微信","WeChat Pay"))
                    DonationCode(name:"Donate-Alipay",title:model.text("支付宝","Alipay"))
                }
            }
            Button(model.text("查看使用引导","Show welcome guide"),action:guide).buttonStyle(.link)
        }.padding(28).frame(width:420)
            .preferredColorScheme(.dark)
            .environment(\.locale,Locale(identifier:model.language.rawValue))
    }
}

private struct LinkRow:View {
    let symbol:String, title:String, detail:String, url:URL
    var body:some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing:12) {
                Image(systemName:symbol).frame(width:18).foregroundStyle(.cyan)
                Text(title)
                Spacer()
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName:"arrow.up.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal,14).frame(height:40).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct DonationCode:View {
    let name:String, title:String
    var body:some View {
        VStack(spacing:8) {
            if let url=AppInfo.resource(name,"png"),let image=NSImage(contentsOf:url) {
                Image(nsImage:image).resizable().interpolation(.high).scaledToFit().frame(width:140,height:140)
                    .clipShape(RoundedRectangle(cornerRadius:8))
            } else {
                RoundedRectangle(cornerRadius:8).strokeBorder(.white.opacity(0.18),style:StrokeStyle(lineWidth:1,dash:[4,4])).frame(width:140,height:140)
            }
            Text(title).font(.system(size:12)).foregroundStyle(.secondary)
        }
    }
}
