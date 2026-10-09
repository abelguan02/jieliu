import AppKit
import CoreText

enum Fonts {
    static func register() {
        if let url=Bundle.main.url(forResource:"GeistMono-Medium",withExtension:"ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
            return
        }
        // Keep command-line previews identical to the packaged app without a system font install.
        let source=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("apps/macos/Resources/GeistMono-Medium.ttf.b64")
        if let encoded=try? String(contentsOf:source,encoding:.utf8),let data=Data(base64Encoded:encoded,options:.ignoreUnknownCharacters),
           let provider=CGDataProvider(data:data as CFData),let font=CGFont(provider) {
            CTFontManagerRegisterGraphicsFont(font,nil)
        }
    }
}
