import ScreenCaptureKit

enum FullScreenWindowDetector {
    static func matches(_ window: SCWindow, processIdentifier: pid_t, display: SCDisplay, menuBarHeight: CGFloat) -> Bool {
        guard window.owningApplication?.processID == processIdentifier,
              window.isOnScreen,
              window.windowLayer == 0
        else {
            return false
        }

        let windowFrame = window.frame
        let displayFrame = display.frame
        let tolerance: CGFloat = 4
        let topInset = windowFrame.minY - displayFrame.minY
        let validTopInset = topInset >= -tolerance && topInset <= menuBarHeight + tolerance
        let fillsDisplayWidth = abs(windowFrame.minX - displayFrame.minX) <= tolerance
            && abs(windowFrame.maxX - displayFrame.maxX) <= tolerance
        let reachesDisplayBottom = abs(windowFrame.maxY - displayFrame.maxY) <= tolerance

        return validTopInset && fillsDisplayWidth && reachesDisplayBottom
    }
}
