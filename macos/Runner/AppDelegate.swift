import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Open at the macOS "zoom" size (fills the screen's visible area, minus the
    // menu bar / Dock — NOT true fullscreen), reusing the same zoom() the title
    // bar's double-click calls. Deferred one run-loop turn: at this point the
    // Flutter window isn't in NSApp.windows yet (and has no screen), so a
    // synchronous zoom would find nothing / no-op. After state restoration has
    // settled a restored frame can't clobber it; the isZoomed guard makes this
    // "ensure zoomed" so an already-zoomed restored window isn't toggled down.
    DispatchQueue.main.async {
      guard
        let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }),
        !window.isZoomed
      else { return }
      window.zoom(nil)
    }
  }
}
