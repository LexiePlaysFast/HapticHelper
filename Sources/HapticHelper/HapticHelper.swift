// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

@main
struct HapticHelper {

  static func main() async throws {
    let translator = Translator()

    Task {

      while let line = readLine() {
        await translator.clInput(line: line)
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
