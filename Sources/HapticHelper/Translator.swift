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

  enum PowerLevel: String, RawRepresentable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
  }

  enum CachedCommand {
    case stop
    case connect(deviceIndex: Int)
    case vibrate(deviceIndex: Int, power: Double)
    case pulse(deviceIndex: Int, power: PowerLevel)
    case heartbeat(deviceIndex: Int, power: PowerLevel)

    var deviceIndex: Int {
      switch self {
      case .connect(let deviceIndex): return deviceIndex
      case .vibrate(let deviceIndex, _): return deviceIndex
      case .pulse(let deviceIndex, _): return deviceIndex
      case .heartbeat(let deviceIndex, _): return deviceIndex
      default: preconditionFailure()
      }
    }
  }

  enum CommandName: String, RawRepresentable {
    case stop = "STOP"
    case connect = "CONNECT"
    case vibrate = "VIBRATE"
    case pulse = "PULSE"
    case heartbeat = "HEARTBEAT"
  }

  fileprivate func parse(command: String) -> CachedCommand? {
    let elements = command.split(separator: " ")

    guard
      elements.count > 0
    else {
      // empty string, ignoring
      return nil
    }

    let commandName = String(elements.first!)

    guard
      let commandName = CommandName(rawValue: commandName)
    else {
      print("!! Unknown command `\(commandName)")

      return nil
    }

    switch commandName {
    case .stop:
      return .stop

    case .connect:
      guard
        elements.count == 2,
        let deviceIndex = Int(elements[1])
      else {
        print("!! Invalid arguments, expected device index")

        return nil
      }

      return .connect(deviceIndex: deviceIndex)

    case .vibrate:
      guard
        elements.count == 3,
        let deviceIndex = Int(elements[1]),
        let power = Double(elements[2])
      else {
        print("!! Invalid arguments, expected device index, power level")

        return nil
      }

      return .vibrate(deviceIndex: deviceIndex, power: power)

    case .pulse:
      guard
        elements.count == 3,
        let deviceIndex = Int(elements[1]),
        let power = PowerLevel(rawValue: String(elements[2]))
      else {
        print("!! Invalid arguments, expected device index, power level")

        return nil
      }

      return .pulse(deviceIndex: deviceIndex, power: power)

    case .heartbeat:
      guard
        elements.count == 3,
        let deviceIndex = Int(elements[1]),
        let power = PowerLevel(rawValue: String(elements[2]))
      else {
        print("!! Invalid arguments, expected device index, power level")

        return nil
      }

      return .heartbeat(deviceIndex: deviceIndex, power: power)
    }
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
    case ScanningFinished(Id: Int)
    case Ok(Id: Int)
    case ServerInfo(Id: Int, MessageVersion: Int, MaxPingTime: Int, ServerName: String?)
    case DeviceList(Id: Int, Devices: [Device])
    case DeviceAdded(Id: Int, DeviceIndex: Int)
    case DeviceRemoved(Id: Int, DeviceIndex: Int)

    case StopAllDevices(Id: Int)

    var identifier: Int {
      switch self {
      case .RequestServerInfo(let Id, _, _): return Id
      case .RequestDeviceList(let Id): return Id
      case .StartScanning(let Id): return Id
      case .StopScanning(let Id): return Id
      case .ScanningFinished(let Id): return Id
      case .Ok(let Id): return Id
      case .ServerInfo(let Id, _, _, _): return Id
      case .DeviceList(let Id, _): return Id
      case .DeviceAdded(let Id, _): return Id
      case .DeviceRemoved(let Id, _): return Id
      case .StopAllDevices(let Id): return Id
      }
    }
  }

  fileprivate var isScanning = false

  let eventChannel = AsyncChannel<String>()

  fileprivate var _nextEventIndex = 1

  var nextEventIndex: Int {
    let nextEventIndex = _nextEventIndex
    _nextEventIndex += 1
    return nextEventIndex
  }

  fileprivate var eventCache: [Int: RequestWrapper] = [:]
  fileprivate var devices: [Int: Device] = [:]
  fileprivate var cachedCommands: [Int: [CachedCommand]] = [:]

  func clInput(line: String) async {
    guard
      let command = parse(command: line)
    else {
      return
    }

    switch command {
    case .stop:
      await stopAllDevices()

    default:
      await run(command)
    }

    print("\(command)")
  }

  fileprivate func run(_ command: CachedCommand) async {
    if let device = devices[command.deviceIndex] {
      // send message to device
    } else {
      // cache message until connection can be established
    }
  }

  fileprivate func stopAllDevices() async {
    print("!! Stopping all devices.")

    await send(
      .StopAllDevices(
        Id: nextEventIndex
      ),
    )
  }

  fileprivate func register(device: Device) {
    // print("registering ``\(device.DeviceName)'' as #\(device.DeviceIndex)")

    self.devices[device.DeviceIndex] = device
  }

  func process(line: String) async throws {
    let input = try! decoder.decode([RequestWrapper].self, from: line.data(using: .utf8)!)

    for response in input {
      switch response {
      case .DeviceRemoved(_, let deviceIndex):
        print("!! Device \(deviceIndex) disconnected.")

        devices[deviceIndex] = nil

      case .DeviceAdded:
        await requestDeviceList()

      case .DeviceList(_, let devices):
        for device in devices {
          register(device: device)
        }

      case .ServerInfo:
        await completeHandshake(response)
      case .Ok:
        await discharge(response)

      default:
        print("undefined action: \(response)")

        break
      }
    }
  }

  fileprivate func checkCommandCache() async {
    if cachedCommands.count > 0 {
      print("!! Unable to discover all devices. Starting new scan.")

      await scan()
    }
  }

  fileprivate func send(_ requests: RequestWrapper...) async {
    try! await send(requests: requests)
  }

  fileprivate func send(requests: [RequestWrapper]) async throws {
    for request in requests {
      eventCache[request.identifier] = request
    }

    let requestData = try encoder.encode(requests)
    let requestString = String(data: requestData, encoding: .utf8)!

    await eventChannel.send(requestString)
  }

  fileprivate func completeHandshake(_ response: RequestWrapper) async {
    await discharge(response)
  }

  fileprivate func discharge(_ response: RequestWrapper) async {
    let originalRequest = eventCache[response.identifier]!

    switch originalRequest {
    case .StartScanning:
      isScanning = true

    case .StopScanning:
      isScanning = false
      await checkCommandCache()

    default:
      // Most messages don't require any kind of response

      break
    }

    eventCache[response.identifier] = nil
  }

  fileprivate func scan(for seconds: TimeInterval = 30.0) async {
    guard
      !isScanning
    else {
      return
    }

    await send(
      .StartScanning(
        Id: nextEventIndex
      ),
    )

    try? await Task.sleep(nanoseconds: UInt64(Double(1_000_000_000) * seconds))

    await send(
      .StopScanning(
        Id: nextEventIndex
      ),
    )
  }

  func doHandshake() async {
    await send(
      .RequestServerInfo(
        Id: nextEventIndex,
        MessageVersion: 2,
        ClientName: "HapticHelper"
      ),
    )

    await requestDeviceList()

    await scan()
  }

  fileprivate func requestDeviceList() async {
    await send(
      .RequestDeviceList(
        Id: nextEventIndex
      ),
    )
  }

}
