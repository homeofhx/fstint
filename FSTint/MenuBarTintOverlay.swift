import AppKit
import QuartzCore

@MainActor
final class MenuBarTintOverlay {

    private var panel: TintPanel?
    private var shouldBeVisible = false
    private var isTemporarilyHidden = false

    func show(columnImage: CGImage, on screen: NSScreen, height: CGFloat) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let extraPixelHeight = 1 / screen.backingScaleFactor
        let tintFrame = CGRect(x: screen.frame.minX,
                               y: screen.frame.maxY - height - extraPixelHeight,
                               width: screen.frame.width,
                               height: height + extraPixelHeight)

        panel.setFrame(tintFrame, display: false)
        panel.colorSpace = screen.colorSpace
        if let layer = panel.contentView?.layer {
            if layer.contents != nil {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.5
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(transition, forKey: "FSTint.colorTransition")
            }

            layer.contents = columnImage
            layer.contentsGravity = .resize
            layer.contentsScale = screen.backingScaleFactor
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
        }
        shouldBeVisible = true

        if !isTemporarilyHidden {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        shouldBeVisible = false
        isTemporarilyHidden = false
        panel?.orderOut(nil)
    }

    func setTemporarilyHidden(_ hidden: Bool) {
        guard hidden != isTemporarilyHidden else { return }
        isTemporarilyHidden = hidden

        if hidden {
            panel?.orderOut(nil)
        } else if shouldBeVisible {
            panel?.alphaValue = 1
            panel?.orderFrontRegardless()
        }
    }

    private func makePanel() -> TintPanel {
        let panel = TintPanel(contentRect: .zero,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView?.wantsLayer = true
        return panel
    }

}

private final class TintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
