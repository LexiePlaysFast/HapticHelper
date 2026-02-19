// Copyright (c) 2026 Lexie T
// Licensed under the terms of GPL v3.0 or later, see LICENSE

import Foundation

@main
struct HapticHelper {

  static func main() async throws {
    var rules: [DeviceResolver.DeviceRule] = []

    do {
      let fileURL = URL(fileURLWithPath: "~/.config/haptics.conf".expandingTildeInPath)

      print(fileURL)

      let data = try String(contentsOf: fileURL, encoding: .utf8)

      print("?? Using config file at `\(fileURL.path)'")

      for line in data.components(separatedBy: .newlines) {
        let line = line.trimmingCharacters(in: .whitespaces)

        guard
          line.count > 0,
          line.first != "#"
        else {
          continue
        }

        let components = line.split(separator: " ", maxSplits: 1)

        guard
          components.count == 2,
          let command = components.first.map(String.init),
          let arguments = components.last.map(String.init),
          command == "alias",
          let rule = DeviceResolver.DeviceRule(arguments)
        else {
          print("!! Invalid config command `\(line)', ignoring")

          continue
        }

        rules.append(rule)
      }
    } catch {
      // no worries
    }

    let resolver = DeviceResolver(rules: rules)
    let translator = Translator(resolver: resolver)

    Task {

      while let line = readLine() {
        try! await translator.clInput(line: line)
      }

      try! await translator.gracefulStop()

      exit(0)
    }

    let client = Client(
      host: "localhost",
      port: 12345,
      eventLoopGroup: .singleton,
      translator: translator
    )

    try await client.run()
  }

}
