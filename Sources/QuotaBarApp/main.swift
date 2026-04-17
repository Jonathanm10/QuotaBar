import AppKit
import SwiftUI
import QuotaBarCore

let args = CommandLine.arguments

if args.count >= 3, args[1] == "--snapshot" {
    let path = args[2]
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    SnapshotRunner.render(to: path)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
