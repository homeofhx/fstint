import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: TintController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.status == .permissionRequired {
                permissionLine
                Divider()
                QuitMenuEntry()
            } else {
                statusLine
                Divider()

                HStack(spacing: 22) {
                    Toggle("Activate FSTint", isOn: $controller.isEnabled)
                    Toggle("Launch at Login", isOn: $controller.launchAtLogin)
                }.toggleStyle(.checkbox)

                QuitMenuEntry()
            }
        }.padding(13).frame(width: 325)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch controller.status {
        case .disabled:
            Text("FSTint is inactive")
        case .permissionRequired:
            EmptyView()
        case .noBuiltInDisplay:
            Text("FSTint can't find the built-in display")
        case .waiting:
            Text("FSTint is waiting for a full-screen application")
        case let .tinting(applicationName):
            Text("FSTint is tinting \(applicationName)").lineLimit(1)
        case .error:
            Text("FSTint couldn't sample the full-screen application")
        }
    }

    private var permissionLine: some View {
        HStack(spacing: 8) {
            Text("FSTint needs Screen Recording permission")
            Button("Grant") { controller.requestScreenRecordingPermission() }.buttonStyle(.borderedProminent)
        }.controlSize(.small)
    }

}

private struct QuitMenuEntry: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            HStack {
                Text("Quit!")
                Spacer()
                Text("Command + Esc").foregroundStyle(isHovered ? Color.white.opacity(0.8) : Color(nsColor: .secondaryLabelColor))
            }.padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: .command)
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background(isHovered ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .frame(maxWidth: .infinity)
            .onHover { isHovered = $0 }
    }
}
