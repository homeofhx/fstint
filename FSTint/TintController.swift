import AppKit
import Combine
import CoreGraphics
import ScreenCaptureKit
import ServiceManagement

enum TintStatus: Equatable {
    case disabled
    case permissionRequired
    case noBuiltInDisplay
    case waiting
    case tinting(String)
    case error
}

@MainActor
final class TintController: ObservableObject {

    static let shared = TintController()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Defaults.enabled)
            if isEnabled {
                refreshNow()
            } else {
                status = .disabled
                overlay.hide()
            }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            updateLaunchAtLogin(shouldLaunch: launchAtLogin)
        }
    }

    @Published private(set) var status: TintStatus = .waiting

    var menuBarSymbol: String {
        switch status {
        case .tinting:
            return "rectangle.topthird.inset.filled"
        case .disabled:
            return "rectangle.dashed"
        default:
            return "rectangle.topthird.inset"
        }
    }

    private enum Defaults {
        static let enabled = "FSTint.isEnabled"
    }

    private let overlay = MenuBarTintOverlay()
    private var refreshTimer: Timer?
    private var pointerTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var spaceTransitionTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var lastForegroundApplicationPID: pid_t?
    private var pointerLeftBandAt = Date.distantPast
    private var hasStarted = false

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Defaults.enabled) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        rememberForegroundApplication(NSWorkspace.shared.frontmostApplication)
        observeSystemChanges()
        startTimers()
        refreshNow()
    }

    func stop() {
        refreshTask?.cancel()
        spaceTransitionTask?.cancel()
        refreshTask = nil
        spaceTransitionTask = nil

        refreshTimer?.invalidate()
        pointerTimer?.invalidate()
        refreshTimer = nil
        pointerTimer = nil

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        appObservers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.removeAll()
        appObservers.removeAll()

        overlay.hide()
        hasStarted = false
    }

    func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.evaluateCurrentSpace()
        }
    }

    func requestScreenRecordingPermission() {
        let granted = CGRequestScreenCaptureAccess()
        if granted || CGPreflightScreenCaptureAccess() {
            refreshNow()
        } else {
            status = .permissionRequired
            overlay.hide()
            openScreenRecordingSettings()
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeSystemChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                              object: nil,
                                                              queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    self?.rememberForegroundApplication(application)
                    self?.refreshNow()
                }
            }
        )

        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                              object: nil,
                                                              queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAfterSpaceTransition() }
            }
        )

        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                              object: nil,
                                                              queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }
            }
        )

        appObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                   object: nil,
                                                                   queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }
            }
        )
    }

    private func startTimers() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }

        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointerAvoidance() }
        }
    }

    private func refreshAfterSpaceTransition() {
        refreshNow()
        spaceTransitionTask?.cancel()
        spaceTransitionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    private func evaluateCurrentSpace() async {
        guard isEnabled else {
            status = .disabled
            overlay.hide()
            return
        }

        guard CGPreflightScreenCaptureAccess() else {
            status = .permissionRequired
            overlay.hide()
            return
        }

        guard let builtInDisplay = BuiltInDisplay.current else {
            status = .noBuiltInDisplay
            overlay.hide()
            return
        }

        guard let foregroundApplication = foregroundApplicationForSampling() else {
            status = .waiting
            overlay.hide()
            return
        }

        do {
            let content = try await SCShareableContent.current
            try Task.checkCancellation()

            guard let display = content.displays.first(where: { $0.displayID == builtInDisplay.id }),
                  let application = content.applications.first(where: {
                      $0.processID == foregroundApplication.processIdentifier
                  }),
                  content.windows.contains(where: {
                      FullScreenWindowDetector.matches($0,
                                                       processIdentifier: foregroundApplication.processIdentifier,
                                                       display: display,
                                                       menuBarHeight: builtInDisplay.menuBarHeight)
                  })
            else {
                status = .waiting
                overlay.hide()
                return
            }

            let columnImage = try await ScreenColorSampler.sampleTopColumns(of: application,
                                                                            on: display,
                                                                            belowMenuBarHeight: builtInDisplay.menuBarHeight)
            try Task.checkCancellation()

            let applicationName = foregroundApplication.localizedName ?? application.applicationName
            status = .tinting(applicationName)
            overlay.show(columnImage: columnImage,
                         on: builtInDisplay.screen,
                         height: builtInDisplay.menuBarHeight)
            updatePointerAvoidance()
        } catch is CancellationError {
            return
        } catch {
            status = .error
            overlay.hide()
        }
    }

    private func foregroundApplicationForSampling() -> NSRunningApplication? {
        let current = NSWorkspace.shared.frontmostApplication
        rememberForegroundApplication(current)

        if let current,
           current.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           current.activationPolicy == .regular {
            return current
        }

        guard let lastForegroundApplicationPID else { return nil }
        return NSRunningApplication(processIdentifier: lastForegroundApplicationPID)
    }

    private func rememberForegroundApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular
        else {
            return
        }
        lastForegroundApplicationPID = application.processIdentifier
    }

    private func updatePointerAvoidance() {
        guard case .tinting = status,
              let builtInDisplay = BuiltInDisplay.current
        else {
            overlay.setTemporarilyHidden(false)
            return
        }

        let pointer = NSEvent.mouseLocation
        let displayFrame = builtInDisplay.screen.frame
        let isWithinDisplayWidth = pointer.x >= displayFrame.minX && pointer.x <= displayFrame.maxX
        let isWithinMenuBar = pointer.y >= displayFrame.maxY - builtInDisplay.menuBarHeight - 2
            && pointer.y <= displayFrame.maxY + 1

        if isWithinDisplayWidth && isWithinMenuBar {
            pointerLeftBandAt = .distantFuture
            overlay.setTemporarilyHidden(true)
        } else {
            if pointerLeftBandAt == .distantFuture {
                pointerLeftBandAt = Date()
            }
            if Date().timeIntervalSince(pointerLeftBandAt) > 0.4 {
                overlay.setTemporarilyHidden(false)
            }
        }
    }

    private func updateLaunchAtLogin(shouldLaunch: Bool) {
        do {
            if shouldLaunch {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

}
