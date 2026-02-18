// Copyright (c) 2026 Lexie T
// Licensed under the terms of GPL v3.0 or later, see LICENSE

import Foundation

@main
struct HapticHelper {

  static func main() async throws {
    let resolver = DeviceResolver()
    let translator = Translator(resolver: resolver)

    Task {

      while let line = readLine() {
        try! await translator.clInput(line: line)
      }

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
