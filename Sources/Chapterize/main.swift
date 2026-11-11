import AppKit

// Top-level code isn't main-actor isolated in Swift 5 mode, but it does run on
// the main thread, so assert that and set up the (main-actor) app delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()  // never returns, so `delegate` stays alive
}
