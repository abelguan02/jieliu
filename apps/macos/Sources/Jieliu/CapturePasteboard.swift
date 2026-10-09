import AppKit

/// Supply original pixels lazily, while file-aware destinations receive the archived URL.
final class CapturePasteboard:NSObject,NSPasteboardItemDataProvider {
    let url:URL
    init(url:URL) { self.url=url }
    func item()->NSPasteboardItem {
        let item=NSPasteboardItem()
        item.setString(url.absoluteString,forType:.fileURL)
        item.setDataProvider(self,forTypes:[.png,.tiff])
        return item
    }
    func pasteboard(_ pasteboard:NSPasteboard?,item:NSPasteboardItem,provideDataForType type:NSPasteboard.PasteboardType) {
        if type == .png,url.pathExtension.lowercased() == "png",let data=try? Data(contentsOf:url) { item.setData(data,forType:type); return }
        guard let data=NSImage(contentsOf:url)?.tiffRepresentation else { return }
        if type == .tiff { item.setData(data,forType:type) }
        else if let png=NSBitmapImageRep(data:data)?.representation(using:.png,properties:[:]) { item.setData(png,forType:type) }
    }
}
