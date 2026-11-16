import AppKit
import ImageIO
import Foundation
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
for (name,size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let image=NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let transform=NSAffineTransform();transform.scale(by:CGFloat(size)/1024);transform.concat()
    NSColor(calibratedRed:0.96,green:0.95,blue:0.92,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:60,y:60,width:904,height:904),xRadius:202,yRadius:202).fill()
    NSColor(calibratedRed:0.28,green:0.31,blue:0.85,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:255,y:190,width:510,height:650),xRadius:48,yRadius:48).fill()
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect:NSRect(x:315,y:660,width:260,height:24),xRadius:12,yRadius:12).fill()
    NSBezierPath(roundedRect:NSRect(x:315,y:604,width:340,height:24),xRadius:12,yRadius:12).fill()
    let arrow=NSBezierPath();arrow.move(to:NSPoint(x:510,y:530));arrow.line(to:NSPoint(x:510,y:310));arrow.move(to:NSPoint(x:420,y:400));arrow.line(to:NSPoint(x:510,y:310));arrow.line(to:NSPoint(x:600,y:400))
    NSColor.white.setStroke();arrow.lineWidth=36;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round;arrow.stroke()
    image.unlockFocus()
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent(name+".png"))
}
