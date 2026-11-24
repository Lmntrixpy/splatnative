// SplatNative - SplatNativeApp.swift
import SwiftUI

@main
struct SplatNativeApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup("SplatNative") { LauncherView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
        #else
        WindowGroup { LauncherView() }
        #endif
    }
}
