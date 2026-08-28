import AppKit

if CommandLine.arguments.contains("--diagnostic-list")
  || CommandLine.arguments.contains("--diagnostic-tone")
  || CommandLine.arguments.contains("--diagnostic-capture")
  || CommandLine.arguments.contains("--diagnostic-outputs")
  || CommandLine.arguments.contains("--diagnostic-select-output")
{
  MainActor.assumeIsolated {
    DiagnosticRunner.run(arguments: CommandLine.arguments)
  }
}

@MainActor
private func runApp() {
  let application = NSApplication.shared
  let delegate = AppDelegate()
  application.delegate = delegate
  withExtendedLifetime(delegate) {
    application.run()
  }
}

MainActor.assumeIsolated {
  runApp()
}
