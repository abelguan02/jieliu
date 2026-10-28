import AppKit

/// The same affine pose is used for painting, input and the final arrival frame.
struct LayerPlacement {
    let rect:CGRect
    let front:Bool
    var transform:CGAffineTransform {
        let sx:CGFloat=front ? 1.12 : cos(48 * .pi/180)
        let sy:CGFloat=front ? 1.12 : cos(16 * .pi/180)
        let shear:CGFloat=front ? 0 : sin(16 * .pi/180)*sin(48 * .pi/180)
        return CGAffineTransform(a:sx,b:shear,c:0,d:sy,tx:rect.midX,ty:rect.midY)
    }
    var localRect:CGRect { CGRect(x:-rect.width/2,y:-rect.height/2,width:rect.width,height:rect.height) }
    var path:CGPath {
        var matrix=transform
        return CGPath(rect:localRect,transform:&matrix)
    }
    func converted(scale:CGFloat,offsetY:CGFloat=0)->LayerPlacement {
        LayerPlacement(rect:CGRect(x:rect.minX*scale,y:(rect.minY+offsetY)*scale,width:rect.width*scale,height:rect.height*scale),front:front)
    }
}
