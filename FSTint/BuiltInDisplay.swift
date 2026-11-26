import AppKit
import CoreGraphics

struct BuiltInDisplay {
    let screen: NSScreen
    let id: CGDirectDisplayID
    let menuBarHeight: CGFloat

    static var current: BuiltInDisplay? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }

            let displayID = CGDirectDisplayID(number.uint32Value)
            guard CGDisplayIsBuiltin(displayID) != 0 else { continue }

            let visibleInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let menuBarHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top, visibleInset)
            
            return BuiltInDisplay(screen: screen, id: displayID, menuBarHeight: menuBarHeight)
        }
        
        return nil
    }
}
