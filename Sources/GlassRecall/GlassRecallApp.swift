import AppKit
import GlassRecallCore
import GlassRecallUI
import SwiftUI

@main
struct GlassRecallApp: App {
    @State private var appState: AppState
    @State private var hudController: FloatingHUDController?

    init() {
        let store = try? MemoryStore()
        let state = AppState(store: store, isPreviewSnapshot: false)
        _appState = State(initialValue: state)
        _hudController = State(initialValue: FloatingHUDController(state: state))
    }

    var body: some Scene {
        MenuBarExtra {
            RootPopoverView(state: appState, width: 500)
                .task {
                    await appState.bootstrap()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.stats.isCapturing ? "eye.circle.fill" : "eye.slash.circle")
                if appState.stats.totalMemories > 0 {
                    Text("\(appState.stats.totalMemories)")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
