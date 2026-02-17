// Copyright (c) 2026 Lexie T
// Licensed under the terms of GPL v3.0 or later, see LICENSE

import Foundation

import AsyncAlgorithms

actor Translator {

  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  struct Event {
    let index: Int
  }

  struct Device: Codable {
    struct MessageInfo: Codable {
      let FeatureCount: Int?
      let StepCount: [Int]?
    }

    let DeviceIndex: Int
    let DeviceName: String
    let DeviceMessages: [String: MessageInfo]
  }

  enum RequestWrapper: Codable {
    case RequestServerInfo(Id: Int, MessageVersion: Int, ClientName: String)
    case RequestDeviceList(Id: Int)
    case StartScanning(Id: Int)
    case StopScanning(Id: Int)
    case Ok(Id: Int)
    case ServerInfo(Id: Int, MessageVersion: Int, MaxPingTime: Int, ServerName: String?)
    case DeviceList(Id: Int, Devices: [Device])
    case DeviceAdded(Id: Int, DeviceIndex: Int)
    case DeviceRemoved(Id: Int, DeviceIndex: Int)
  }

  let eventChannel = AsyncChannel<String>()

  fileprivate var _nextEventIndex = 1

  var nextEventIndex: Int {
    let nextEventIndex = _nextEventIndex
    _nextEventIndex += 1
    return nextEventIndex
  }

  var eventCache: [Int: Event] = [:]
  var devices: [Int: Device] = [:]

  func clInput(line: String) async {
    print("event \(nextEventIndex)")

    await eventChannel.send(line)
  }

  func process(line: String) async throws {
    let input = try! decoder.decode([RequestWrapper].self, from: line.data(using: .utf8)!)

    for response in input {
      switch response {
      case .DeviceRemoved(_, let deviceIndex):
        devices[deviceIndex] = nil

      case .DeviceAdded:
        await requestDeviceList()

      case .DeviceList(_, let devices):
        for device in devices {
          print("registering ``\(device.DeviceName)'' as #\(device.DeviceIndex)")

          self.devices[device.DeviceIndex] = device
        }

      case .ServerInfo: fallthrough
      case .Ok:
        break

      default:
        print("undefined action: \(response)")

        break
      }
    }
  }

  func doHandshake() async {
    let requestWrapper: [RequestWrapper] = [
      .RequestServerInfo(
        Id: nextEventIndex,
        MessageVersion: 2,
        ClientName: "HapticHelper"
      ),
      .StartScanning(
        Id: nextEventIndex
      ),
      .RequestDeviceList(
        Id: nextEventIndex
      ),
    ]

    let requestData = try! encoder.encode(requestWrapper)
    let requestString = String(data: requestData, encoding: .utf8)!

    await eventChannel.send(requestString)

    await waitAndStopScanning()
  }

  fileprivate func waitAndStopScanning() async {
    try? await Task.sleep(nanoseconds: 30_000_000_000)

    let requestWrapper: [RequestWrapper] = [
      .StopScanning(
        Id: nextEventIndex
      ),
    ]

    let requestData = try! encoder.encode(requestWrapper)
    let requestString = String(data: requestData, encoding: .utf8)!

    await eventChannel.send(requestString)
  }

  fileprivate func requestDeviceList() async {
    let requestWrapper: [RequestWrapper] = [
      .RequestDeviceList(
        Id: nextEventIndex
      ),
    ]

    let requestData = try! encoder.encode(requestWrapper)
    let requestString = String(data: requestData, encoding: .utf8)!

    await eventChannel.send(requestString)
  }

}
