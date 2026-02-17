//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Substantial portions of this file are adapted from example code from the
// SwiftNIO project, see above. Additions for the purposes of the HapticHelper
// project are copyright (c) 2026 Lexie T,
// and licensed under the Apache License v2.0.

import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
struct Client {
  let host: String
  let port: Int
  let eventLoopGroup: MultiThreadedEventLoopGroup

  let translator: Translator

  enum UpgradeResult {
    case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
    case notUpgraded
  }

  /// This method starts the client and tries to setup a WebSocket connection.
  func run() async throws {
    let upgradeResult: EventLoopFuture<UpgradeResult> = try await ClientBootstrap(group: self.eventLoopGroup)
      .connect(
        host: self.host,
        port: self.port
      ) { channel in
        channel.eventLoop.makeCompletedFuture {
          let upgrader = NIOTypedWebSocketClientUpgrader<UpgradeResult>(
            upgradePipelineHandler: { (channel, _) in
              channel.eventLoop.makeCompletedFuture {
                let asyncChannel = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(
                  wrappingChannelSynchronously: channel
                )
                return UpgradeResult.websocket(asyncChannel)
              }
            }
          )

          var headers = HTTPHeaders()
          headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
          headers.add(name: "Content-Length", value: "0")

          let requestHead = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: "/",
            headers: headers
          )

          let clientUpgradeConfiguration = NIOTypedHTTPClientUpgradeConfiguration(
            upgradeRequestHead: requestHead,
            upgraders: [upgrader],
            notUpgradingCompletionHandler: { channel in
              channel.eventLoop.makeCompletedFuture {
                UpgradeResult.notUpgraded
              }
            }
          )

          let negotiationResultFuture = try channel.pipeline.syncOperations
            .configureUpgradableHTTPClientPipeline(
              configuration: .init(upgradeConfiguration: clientUpgradeConfiguration)
            )

          return negotiationResultFuture
        }
      }

    // We are awaiting and handling the upgrade result now.
    try await self.handleUpgradeResult(upgradeResult)
  }

  /// This method handles the upgrade result.
  private func handleUpgradeResult(_ upgradeResult: EventLoopFuture<UpgradeResult>) async throws {
    switch try await upgradeResult.get() {
    case .websocket(let websocketChannel):
      print("Handling websocket connection")
      try await self.handleWebsocketChannel(websocketChannel)
      print("Done handling websocket connection")
    case .notUpgraded:
      // The upgrade to websocket did not succeed. We are just exiting in this case.
      print("Upgrade declined")
    }
  }

  private func handleWebsocketChannel(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
    try await channel.executeThenClose { inbound, outbound in
      let inboundFuture = eventLoopGroup.any().makeFutureWithTask {

        for try await frame in inbound {
          switch frame.opcode {
          case .pong:
            break
            // print("Received pong: \(String(buffer: frame.data))")

          case .text:
            try await translator.process(line: String(buffer: frame.data));

          case .connectionClose:
            exit(0)

          case .binary, .continuation:
            break

          case .ping:
            // print("Received ping")

            try await outbound.write(WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: frame.data))

            break

          default:
            // Unknown frames are errors.
            exit(1)
          }
        }

      }

      let outboundFuture = eventLoopGroup.any().makeFutureWithTask {

        for await line in translator.eventChannel {
          let pingFrame = WebSocketFrame(fin: true, opcode: .text, maskKey: .random(), data: ByteBuffer(string: line))

          try await outbound.write(pingFrame)
        }

      }

      await translator.doHandshake()

      _ = try await inboundFuture.and(outboundFuture).get()
    }
  }
}
