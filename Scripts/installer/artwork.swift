// The background contains only type, light and the installation arrow.
// Finder draws both icons from the real app and the Applications link.
import AppKit
import CoreGraphics
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r/255, g/255, b/255, a])!
}
for density in [1, 2] {
    let pixelWidth = 800 * density, pixelHeight = 500 * density
    let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                            bytesPerRow: pixelWidth * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(density), y: CGFloat(density))
    let base = CGGradient(colorsSpace: space, colors: [rgb(23,34,58), rgb(13,21,40), rgb(11,17,32)] as CFArray, locations: [0,0.55,1])!
    context.drawLinearGradient(base, start: CGPoint(x: 0,y:500), end: CGPoint(x:800,y:0), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: space, colors: [rgb(231,181,93,0.115),rgb(231,181,93,0.041),rgb(231,181,93,0)] as CFArray, locations: [0,0.49,1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x:223,y:220), startRadius:0,
                               endCenter: CGPoint(x:223,y:220), endRadius:260, options: [])
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    func line(_ text: String, font: NSFont, color: NSColor, centerY: CGFloat, tracking: CGFloat) {
        let attr = NSAttributedString(string:text, attributes:[.font: font, .foregroundColor: color, .kern:tracking])
        let size = attr.size()
        attr.draw(at: NSPoint(x:(800-size.width)/2, y:500-centerY-size.height/2))
    }
    line("A little light for your Mac.", font:.systemFont(ofSize:42,weight:.medium),
         color:NSColor(srgbRed:0.97, green:0.96, blue:0.93, alpha:1),centerY:88,tracking:-1.5)
    line("Drag Firefly to Applications to install.",font:.systemFont(ofSize:18,weight:.regular),
         color:NSColor(srgbRed:0.75,green:0.78,blue:0.83,alpha:1),centerY:135,tracking:0)
    context.setStrokeColor(rgb(231,191,115))
    context.setLineWidth(2); context.setLineCap(.round); context.setLineJoin(.round)
    let y = 500.0 - 277.0
    context.move(to: CGPoint(x:370,y:y)); context.addLine(to: CGPoint(x:430,y:y))
    context.move(to: CGPoint(x:420,y:y+10)); context.addLine(to: CGPoint(x:430,y:y)); context.addLine(to: CGPoint(x:420,y:y-10));context.strokePath()
    // Finder uses black filenames over a picture background, even in dark
    // appearance. Small inset labels provide contrast without duplicating text.
    for (x, width) in [(218.0, 88.0), (582.0, 118.0)] {
        let label = CGRect(x:x-width/2, y:500-359-12, width:width, height:24)
        let shape = CGPath(roundedRect:label, cornerWidth:12, cornerHeight:12, transform:nil)
        context.setFillColor(rgb(182,184,187)); context.addPath(shape); context.fillPath()
    }
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage:context.makeImage()!)
    rep.size = NSSize(width:800,height:500)
    let name = density == 1 ? "install.png" : "install@2x.png"
    try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
}
