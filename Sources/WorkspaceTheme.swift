import SwiftUI
import AppKit

// Approved forest workspace. Native file interaction and light settings remain independent.
enum WorkspaceTheme {
    static let canvas = Color.white
    static let rail = Color(red:0.950,green:0.974,blue:0.958) // Light settings rail.
    static let sidebar = Color(red:0.0,green:0.245,blue:0.190)
    static let sidebarSelection = Color(red:0.0,green:0.410,blue:0.315)
    static let sidebarText = Color(red:0.94,green:0.98,blue:0.96)
    static let sidebarMuted = Color(red:0.77,green:0.88,blue:0.82)
    static let projectCanvas = Color(red:0.964,green:0.986,blue:0.977)
    static let mint = Color(red:0.876,green:0.955,blue:0.925)
    static let peach = Color(red:0.90,green:0.95,blue:0.92)
    static let line = Color(red:0.89,green:0.93,blue:0.91)
    static let ink = Color(red:0.09,green:0.14,blue:0.13)
    static let secondary = Color(red:0.37,green:0.44,blue:0.41)
    static let paper = NSColor.white
    static let projectPaper = NSColor(calibratedRed:0.964,green:0.986,blue:0.977,alpha:1)
    static let selection = NSColor(calibratedRed:0.876,green:0.955,blue:0.925,alpha:1)
    static let section = NSColor(calibratedRed:0.935,green:0.978,blue:0.961,alpha:1)
    static let folder: NSImage = {
        let image = NSImage(size:NSSize(width:32,height:30),flipped:false) { _ in
            let tab = NSBezierPath(roundedRect:NSRect(x:2,y:15,width:14,height:12),xRadius:4,yRadius:4)
            NSColor(calibratedRed:1,green:0.76,blue:0.26,alpha:1).setFill(); tab.fill()
            let body = NSBezierPath(roundedRect:NSRect(x:2,y:3,width:28,height:21),xRadius:5,yRadius:5)
            NSGradient(starting:NSColor(calibratedRed:1,green:0.88,blue:0.43,alpha:1),ending:NSColor(calibratedRed:1,green:0.73,blue:0.20,alpha:1))?.draw(in:body,angle:-90)
            NSColor(calibratedRed:0.86,green:0.57,blue:0.12,alpha:1).setStroke(); body.lineWidth = 0.7; body.stroke()
            let shine = NSBezierPath(); shine.move(to:NSPoint(x:7,y:21)); shine.line(to:NSPoint(x:25,y:21)); shine.lineWidth = 1
            NSColor.white.withAlphaComponent(0.65).setStroke(); shine.stroke()
            return true
        }; image.isTemplate = false; return image
    }()
}

struct SoftWorkspaceButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var peach = false
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.system(size:13,weight:.medium,design:.rounded))
            .padding(.horizontal,12).frame(minHeight:32)
            .background(peach ? WorkspaceTheme.peach : WorkspaceTheme.canvas,in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(WorkspaceTheme.line.opacity(0.7),lineWidth:1))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.65 : 1)
    }
}
