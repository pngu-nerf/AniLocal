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

  /// Set when this launch found another AniLocal already running: it hands
  /// over and quits, and asks Dart for nothing on the way out.
  private var yieldingToRunningInstance = false

  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    // Single instance. Two copies of the app share one cache database and one
    // libmpv, and the second one to write wins — a launch from the Dock while
    // a scan runs in the first is the common way to get there. Instead the
    // second launch brings the first to the front and leaves.
    guard let bundleId = Bundle.main.bundleIdentifier else { return }
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
      .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    guard let existing = others.first else { return }
    yieldingToRunningInstance = true
    existing.activate(options: [.activateAllWindows])
    NSApp.terminate(nil)
  }

  /// Cmd-Q, the Dock's Quit, a logout: give Dart its turn BEFORE the process
  /// ends. The runner used to terminate at once, so the tree was never
  /// unmounted and the player's last position, the log's buffered lines and
  /// a running scan's cancellation never ran. `.terminateLater` holds the
  /// quit until Dart replies (see `MainFlutterWindow.prepareToQuit`) or the
  /// fallback timer fires — the same budget Dart gives its hooks — so an
  /// unresponsive Dart side can never make the app refuse to quit.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if yieldingToRunningInstance { return .terminateNow }
    guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow
    else { return .terminateNow }
    var replied = false
    let finish = {
      guard !replied else { return }
      replied = true
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    window.prepareToQuit(completion: finish)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: finish)
    return .terminateLater
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
    // Only on a FIRST launch: once the user has sized the window, the saved
    // frame (setFrameAutosaveName in MainFlutterWindow) is what they expect.
    let saved = UserDefaults.standard.object(
      forKey: "NSWindow Frame \(MainFlutterWindow.frameAutosaveKey)")
    guard saved == nil else { return }
    DispatchQueue.main.async {
      guard
        let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }),
        !window.isZoomed
      else { return }
      window.zoom(nil)
    }
  }
}
