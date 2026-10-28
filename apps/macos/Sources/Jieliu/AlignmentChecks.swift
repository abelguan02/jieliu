import AppKit
import TrayCore

enum AlignmentChecks {
    static func bitmap(size:CGSize,draw:()->Void)->NSBitmapImageRep {
        let image=NSImage(size:size)
        image.lockFocusFlipped(true); draw(); image.unlockFocus()
        return NSBitmapImageRep(data:image.tiffRepresentation!)!
    }
    static func inkBounds(_ bitmap:NSBitmapImageRep,size:CGSize,area:CGRect)->CGRect? {
        let scale=CGFloat(bitmap.pixelsWide)/size.width
        var left=bitmap.pixelsWide, right=0, top=bitmap.pixelsHigh, bottom=0
        for y in Int(area.minY*scale)..<min(bitmap.pixelsHigh,Int(area.maxY*scale)) {
            for x in Int(area.minX*scale)..<min(bitmap.pixelsWide,Int(area.maxX*scale)) {
                guard let pixel=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),pixel.alphaComponent>0.1 else { continue }
                left=min(left,x); right=max(right,x+1); top=min(top,y); bottom=max(bottom,y+1)
            }
        }
        return right>left ? CGRect(x:CGFloat(left)/scale,y:CGFloat(top)/scale,width:CGFloat(right-left)/scale,height:CGFloat(bottom-top)/scale) : nil
    }
    static func samePixels(_ actual:NSBitmapImageRep,_ expected:NSBitmapImageRep,size:CGSize,area:CGRect,reason:String) {
        let scale=CGFloat(actual.pixelsWide)/size.width
        for y in Int(area.minY*scale)..<Int(area.maxY*scale) {
            for x in Int(area.minX*scale)..<Int(area.maxX*scale) {
                let a=actual.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                let b=expected.colorAt(x:x,y:y)!.usingColorSpace(.sRGB)!
                precondition(max(abs(a.redComponent-b.redComponent),abs(a.greenComponent-b.greenComponent),abs(a.blueComponent-b.blueComponent),abs(a.alphaComponent-b.alphaComponent))<0.01,reason)
            }
        }
    }
    static func run(_ model:AppModel) {
        let saved=(model.history,model.language,model.concept,model.animations)
        defer { model.history=saved.0; model.language=saved.1; model.concept=saved.2; model.animations=saved.3 }
        model.animations=false
        let view=TrayView(model:model)
        func populate(_ sizes:[CGSize]) {
            model.history=TrayHistory()
            for (index,size) in sizes.enumerated() {
                model.history.insert(Capture(url:URL(fileURLWithPath:"/synthetic/\(index).png"),date:Date(timeIntervalSince1970:Double(index)*73),width:Int(size.width),height:Int(size.height)))
            }
        }
        for width:CGFloat in [900,1100,1440] {
            view.frame=CGRect(x:0,y:0,width:width,height:270)
            for sizes in [Array(repeating:CGSize(width:200,height:1000),count:8),Array(repeating:CGSize(width:16384,height:2160),count:8),[CGSize(width:200,height:1000),CGSize(width:1600,height:900),CGSize(width:900,height:1600)]] {
                populate(sizes)
                let placements=view.rulerLayout()
                for pair in zip(placements,placements.dropFirst()) {
                    precondition(pair.0.caption.maxX+12 <= pair.1.caption.minX,"A: screenshot captions overlap")
                }
                for item in placements {
                    precondition(item.shot.minX==item.caption.minX && item.caption.maxX<=view.designWidth-24)
                    precondition(item.caption.width-Ink.textWidth("00:00")-18>0)
                }
            }
            for count in [0,1,2,8] {
                populate(Array(repeating:CGSize(width:640,height:400),count:count))
                for spread:CGFloat in [0.51,0.6,0.85,1] {
                    view.spread=spread
                    let gap=view.layerGap(), start=view.designWidth/2-CGFloat(max(0,count-1))*gap/2
                    let captions=(0..<count).map { view.layerCaptionRect(center:start+CGFloat($0)*gap,gap:gap) }
                    for pair in zip(captions,captions.dropFirst()) {
                        precondition(pair.1.minX-pair.0.maxX>=11.99,"C: moving captions overlap")
                    }
                    if let first=captions.first,let last=captions.last {
                        precondition(abs((first.minX+last.maxX)/2-view.designWidth/2)<0.01)
                        precondition(first.minX>=24 && last.maxX<=view.designWidth-24)
                    }
                }
            }
        }
        for text in ["00:00:00","读取","写入","READ","WRITE","—","8 个图层 · 最新 00:00:00","8 layers · Latest 00:00:00","没有图层","No layers"] {
            let size=CGSize(width:400,height:40)
            for alignment in [NSTextAlignment.right,.center] {
                let bitmap=bitmap(size:size) { Ink.text(text,200,8,size:10.5,color:.white,alignment:alignment) }
                let bounds=inkBounds(bitmap,size:size,area:CGRect(origin:.zero,size:size))!
                let anchor=alignment == .right ? bounds.maxX : bounds.midX
                precondition(abs(anchor-200)<2,"Localized text lost its alignment anchor")
            }
        }
        view.frame=CGRect(x:0,y:0,width:1100,height:270)
        view.expanded=true; view.openness=1; view.hovered=nil
        for language in AppLanguage.allCases {
            model.language=language; model.concept = .buffer
            populate(Array(repeating:CGSize(width:640,height:400),count:4))
            let bitmap=bitmap(size:view.bounds.size) { view.draw(view.bounds) }
            for slot in 0..<8 {
                let left=view.designWidth/2-474+CGFloat(slot)*120
                let area=CGRect(x:left+42,y:view.top+87,width:66,height:15)
                let capture=model.history.slots[slot].flatMap { id in model.history.items.first { $0.id==id } }
                let reference=self.bitmap(size:view.bounds.size) {
                    Ink.box(view.bounds,color:.black)
                    Ink.text(capture.map { Ink.clock($0.date) } ?? "—",left+108,view.top+87,size:10.5,color:Ink.color(0x6d727b),alignment:.right)
                }
                samePixels(bitmap,reference,size:view.bounds.size,area:area,reason:"B: timestamp/empty state lost its measured right anchor")
            }
        }
        model.concept = .ruler
        let ruler=bitmap(size:view.bounds.size) { view.draw(view.bounds) }
        let scale=CGFloat(ruler.pixelsWide)/view.bounds.width
        let firstTick=ceil((view.folderRect.minX+12)/10)*10+0.5
        for x in stride(from:firstTick,to:view.folderRect.maxX-12,by:10) {
            let tick=ruler.colorAt(x:Int(x*scale),y:Int((view.top+19)*scale))!.usingColorSpace(.sRGB)!
            let plain=ruler.colorAt(x:Int((x+3)*scale),y:Int((view.top+19)*scale))!.usingColorSpace(.sRGB)!
            precondition(abs(tick.redComponent-plain.redComponent)<0.02,"A: ruler ticks show through folder button")
        }
        populate(Array(repeating:CGSize(width:1600,height:900),count:8))
        let plain=bitmap(size:view.bounds.size) { view.draw(view.bounds) }
        view.hovered=model.history.items.last!.id
        let hover=bitmap(size:view.bounds.size) { view.draw(view.bounds) }
        samePixels(hover,plain,size:view.bounds.size,area:view.folderRect,reason:"A: hovered column paints over archive button")
        view.hovered=nil; model.concept = .layers; view.spread=1
        OffscreenChecks.paint(view)
        precondition(view.hitPaths.values.allSatisfy { !$0.boundingBox.intersects(view.folderRect) },"C: expanded cards overlap archive header")
        print("PASS: native A mixed/portrait caption spacing, C expanding label bounds, bilingual glyph anchors and B rendered timestamp/empty alignment")
    }
}
