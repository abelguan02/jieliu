import AppKit
import TrayCore

enum ReviewRegressionChecks {
    static func run(_ model:AppModel) {
        let saved=(model.history,model.selection,model.concept,model.animations,model.sound,model.reduceMotion,model.onCapture,model.onChange)
        defer {
            model.onCapture=saved.6; model.onChange=saved.7
            model.history=saved.0; model.selection=saved.1; model.concept=saved.2; model.animations=saved.3
            model.sound=saved.4; model.reduceMotion=saved.5
        }
        model.history=TrayHistory(); model.animations=true
        for i in 0..<8 {
            model.history.insert(Capture(url:URL(fileURLWithPath:"/synthetic/review-\(i).png"),width:i%2 == 0 ? 200 : 640,height:i%2 == 0 ? 1000 : 400))
        }
        let view=TrayView(model:model)
        view.frame=CGRect(x:0,y:0,width:1100,height:270)
        view.expanded=true; view.openness=1; view.hovering=true; view.spread=1
        for concept in [Concept.ruler,.layers] {
            model.concept=concept; OffscreenChecks.paint(view)
            for capture in model.history.items {
                let drawn=view.layout[capture.id]!, target=view.destinationRect(for:capture)!
                precondition(abs(drawn.midX-target.midX)<0.01,"Arrival target differs from actual \(concept) card")
            }
        }
        for concept in [Concept.ruler,.layers] {
            model.concept=concept; view.synchronizeState()
            for width:CGFloat in [900,1440] {
                view.frame=CGRect(x:0,y:0,width:width,height:270)
                for openness:CGFloat in [0.4,1] {
                    for spread:CGFloat in [0,0.7,1] {
                        view.openness=openness; view.spread=spread
                        for capture in model.history.items {
                            view.hovered=capture.id
                            OffscreenChecks.paint(view)
                            let target=view.destinationRect(for:capture)!
                            let effect=CaptureEffect(image:NSImage(size:CGSize(width:capture.width,height:capture.height)),source:CGRect(x:300,y:100,width:240,height:120),target:target,concept:concept,top:32)
                            effect.frame=CGRect(x:0,y:0,width:width,height:500)
                            effect.updateDestination(from:view,capture:capture); effect.progress=1
                            OffscreenChecks.paint(effect)
                            let path=view.hitPaths[capture.id]!, r=path.boundingBox
                            let expected=CGRect(x:r.minX*view.scale,y:r.minY*view.scale,width:r.width*view.scale,height:r.height*view.scale)
                            let actual=effect.imagePath.boundingBox
                            precondition(abs(expected.minX-actual.minX)<0.01 && abs(expected.minY-actual.minY)<0.01 && abs(expected.width-actual.width)<0.01 && abs(expected.height-actual.height)<0.01,"Final effect geometry differs from visible card")
                            view.spread=1-spread
                            OffscreenChecks.paint(view); effect.updateDestination(from:view,capture:capture); OffscreenChecks.paint(effect)
                            let updated=view.hitPaths[capture.id]!.boundingBox
                            precondition(abs(effect.imagePath.boundingBox.midX-updated.midX*view.scale)<0.01,"Arrival did not follow expanding layout")
                            view.spread=spread
                        }
                    }
                }
            }
        }
        for concept in [Concept.ruler,.layers] {
            model.concept=concept; view.synchronizeState(); view.openness=1; view.spread=1
            let active=model.history.items[0]
            let effect=CaptureEffect(image:NSImage(size:CGSize(width:active.width,height:active.height)),source:CGRect(x:300,y:100,width:240,height:120),target:view.destinationRect(for:active)!,concept:concept,top:32)
            effect.frame=CGRect(x:0,y:0,width:view.bounds.width,height:500); effect.progress=1
            for i in 0..<4 {
                model.receive(Capture(url:URL(fileURLWithPath:"/synthetic/burst-\(concept.rawValue)-\(i).png"),width:100,height:2000))
                OffscreenChecks.paint(view); effect.updateDestination(from:view,capture:active); OffscreenChecks.paint(effect)
                let drawn=view.hitPaths[active.id]!.boundingBox
                precondition(abs(effect.imagePath.boundingBox.midX-drawn.midX*view.scale)<0.01,"Burst left an in-flight image targeting its old column")
            }
        }
        model.concept = .ruler; view.openness=1
        let before=view.rulerLayout().map(\.shot)
        view.arrived[model.history.items[0].id]=CACurrentMediaTime()
        let after=view.rulerLayout().map(\.shot)
        precondition(before==after,"Animated dimension text changed reserved ruler layout")
        view.arrived.removeAll()
        model.concept = .buffer
        view.synchronizeState()
        let ids=model.history.slots.compactMap { $0 }
        model.selection=[ids[0]]
        let right=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.shift,timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:124)!
        for _ in 0..<3 { view.keyDown(with:right) }
        precondition(model.selection==Set(ids.prefix(4)),"Consecutive Shift+Right stops at second image")
        let left=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.shift,timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:123)!
        model.selection=[ids[3]]
        for _ in 0..<3 { view.keyDown(with:left) }
        precondition(model.selection==Set(ids.prefix(4)),"Consecutive Shift+Left did not extend")
        let click=OffscreenChecks.event(.zero,flags:.command)
        view.beginPress(ids[6],event:click); view.mouseUp(with:click)
        let plainRight=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:124)!
        view.keyDown(with:plainRight)
        precondition(model.selection==[ids[7]],"Arrow did not resume from clicked item")
        for i in 0..<8 { model.receive(Capture(url:URL(fileURLWithPath:"/synthetic/replacement-\(i).png"),width:640,height:400)) }
        view.synchronizeState(); view.keyDown(with:plainRight)
        precondition(model.selection==[model.history.slots[0]!],"Evicted keyboard position retained stale selection")
        var sounds=0
        let controller=TrayController(model:model,presentWindows:false,playCaptureSound:{ sounds+=1 })
        for mode in 0..<3 {
            model.animations=mode != 1; model.reduceMotion={ mode==2 }
            for sound in [false,true] {
                model.sound=sound
                let count=sounds
                let capture=Capture(url:URL(fileURLWithPath:"/synthetic/sound-\(mode)-\(sound).png"),width:640,height:400)
                model.receive(capture); model.receive(capture); controller.synchronizeState()
                precondition(sounds==count+(sound ? 1 : 0),"Capture sound depends on animation or repeats on duplicate")
            }
        }
        print("PASS: A/C shared and moving arrival poses, stable caption layout, keyboard extension/eviction and independent sound dispatch without audio")
    }
}
