// Copyright (c) 2026 Lexie T
// Licensed under the terms of GPL v3.0 or later, see LICENSE

import Foundation

import AsyncAlgorithms

actor Translator {

  let resolver: DeviceResolver

  init(resolver: DeviceResolver) {
    self.resolver = resolver
  }

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
    case connect(deviceAddress: DeviceResolver.Resolution)
    case vibrate(deviceAddress: DeviceResolver.Resolution, power: Double)
    case pulse(deviceAddress: DeviceResolver.Resolution, power: PowerLevel)
    case heartbeat(deviceAddress: DeviceResolver.Resolution, power: PowerLevel)

    var deviceAddress: DeviceResolver.Resolution {
      switch self {
      case .connect(let deviceAddress): return deviceAddress
      case .vibrate(let deviceAddress, _): return deviceAddress
      case .pulse(let deviceAddress, _): return deviceAddress
      case .heartbeat(let deviceAddress, _): return deviceAddress
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
        let resolution = resolver.resolve(device: elements[1])
      else {
        print("!! Invalid arguments, expected device index")

        return nil
      }

      return .connect(deviceAddress: resolution)

    case .vibrate:
      guard
        elements.count == 3,
        let resolution = resolver.resolve(device: elements[1]),
        let power = Double(elements[2])
      else {
        print("!! Invalid arguments, expected device index, power level")

        return nil
      }

      return .vibrate(deviceAddress: resolution, power: power)

    case .pulse:
      guard
        elements.count == 3,
        let resolution = resolver.resolve(device: elements[1]),
        let power = PowerLevel(rawValue: String(elements[2]))
      else {
        print("!! Invalid arguments, expected device index, power level")

        return nil
      }

      return .pulse(deviceAddress: resolution, power: power)

    case .heartbeat:
      guard
        elements.count == 3,
        let resolution = resolver.resolve(device: elements[1]),
        let power = PowerLevel(rawValue: String(elements[2]))
      else {
        print("!! Invalid arguments, expected device index, power level")

        return nil
      }

      return .heartbeat(deviceAddress: resolution, power: power)
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

    func vibrateCommands(Id: Int, power: Double) -> [RequestWrapper] {
      guard
        let vibrationInfo = DeviceMessages["VibrateCmd"],
        let featureCount = vibrationInfo.FeatureCount
      else {
        preconditionFailure()
      }

      let featureSpeeds: [FeatureSpeed] = (0 ..< featureCount)
        .map {
          FeatureSpeed(Index: $0, Speed: power)
        }

      return [
        .VibrateCmd(Id: Id, DeviceIndex: DeviceIndex, Speeds: featureSpeeds),
      ]
    }
  }

  struct FeatureSpeed: Codable {
    let Index: Int
    let Speed: Double
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

    case VibrateCmd(Id: Int, DeviceIndex: Int, Speeds: [FeatureSpeed])

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
      case .VibrateCmd(let Id, _, _): return Id
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
  fileprivate var cachedCommands: [CachedCommand] = []

  func clInput(line: String) async throws {
    guard
      let command = parse(command: line)
    else {
      return
    }

    switch command {
    case .stop:
      try await stopAllDevices()

    default:
      try await run(command)
    }
  }

  fileprivate func doPulseCommand(device: Device, power: PowerLevel, offset: Double = 0.0) async throws {
    let decaySteps: Int

    switch power {
    case .low:    decaySteps = 2
    case .medium: decaySteps = 4
    case .high:   decaySteps = 6
    }

    let pulseTime = 480

    for i in 0..<decaySteps {
      try await send(requests: device.vibrateCommands(Id: nextEventIndex, power: Double(decaySteps - i) * 0.10 + offset))
      try await Task.sleep(for: .milliseconds(pulseTime) / decaySteps)
    }
    try await send(requests: device.vibrateCommands(Id: nextEventIndex, power: 0.00))
  }

  fileprivate func doHeartbeatCommand(device: Device, power: PowerLevel) async throws {
    try await doPulseCommand(device: device, power: power, offset: 0.05)

    try await Task.sleep(for: .milliseconds(50))

    try await doPulseCommand(device: device, power: power, offset: 0.0)
  }

  fileprivate func execute(_ command: CachedCommand, device: Device) async throws {
    switch command {
    case .connect:
      break

    case .vibrate(_, let power):
      try await send(requests: device.vibrateCommands(Id: nextEventIndex, power: power))

    case .pulse(_, let power):
      try await doPulseCommand(device: device, power: power)

    case .heartbeat(_, let power):
      try await doHeartbeatCommand(device: device, power: power)

    default:
      exit(1)
    }
  }

  fileprivate func resolvesTo(deviceAddress: DeviceResolver.Resolution, deviceIndex: Int, deviceName: String) -> Bool {
    switch deviceAddress {
    case .first:
      true

    case .name(let string):
      string == deviceName

    case .index(let index):
      index == deviceIndex
    }
  }

  fileprivate func run(_ command: CachedCommand) async throws {
    func resolve(deviceAddress: DeviceResolver.Resolution) -> Device? {
      for (_, device) in devices {
        if resolvesTo(deviceAddress: deviceAddress, deviceIndex: device.DeviceIndex, deviceName: device.DeviceName) {
          return device
        }
      }

      return nil
    }

    if let device = resolve(deviceAddress: command.deviceAddress) {
      try await execute(command, device: device)
    } else {
      print("?? Device not connected, scanning")

      cachedCommands.append(command)

      try await scan()
    }
  }

  func gracefulStop() async throws {
    try await send(
      .StopAllDevices(
        Id: nextEventIndex
      ),
    )

    cachedCommands = []
  }

  fileprivate func stopAllDevices() async throws {
    print("!! Stopping all devices.")

    try await gracefulStop()
  }

  fileprivate func register(device: Device) async throws {
    // print("registering ``\(device.DeviceName)'' as #\(device.DeviceIndex)")

    self.devices[device.DeviceIndex] = device

    let pivot = cachedCommands.partition {
      resolvesTo(deviceAddress: $0.deviceAddress, deviceIndex: device.DeviceIndex, deviceName: device.DeviceName)
    }

    let toDo = cachedCommands[pivot...]
    cachedCommands = Array(cachedCommands[..<pivot])

    if toDo.count > 0 {
      print("?? Connected to device `\(device.DeviceName)', issuing cached commands")

      for command in toDo {
        try await execute(command, device: device)
      }
    }
  }

  func process(line: String) async throws {
    let input = try decoder.decode([RequestWrapper].self, from: line.data(using: .utf8)!)

    for response in input {
      switch response {
      case .DeviceRemoved(_, let deviceIndex):
        print("!! Device `\(devices[deviceIndex]?.DeviceName ?? "Unknown Device")' disconnected.")

        devices[deviceIndex] = nil

      case .DeviceAdded:
        try await requestDeviceList()

      case .DeviceList(_, let devices):
        for device in devices {
          try await register(device: device)
        }

      case .ServerInfo:
        try await completeHandshake(response)
      case .Ok:
        try await discharge(response)

      default:
        print("undefined action: \(response)")

        break
      }
    }
  }

  fileprivate func checkCommandCache() async throws {
    if cachedCommands.count > 0 {
      print("!! Unable to discover all devices. Starting new scan.")

      try await scan()
    }
  }

  fileprivate func send(_ requests: RequestWrapper...) async throws {
    try await send(requests: requests)
  }

  fileprivate func send(requests: [RequestWrapper]) async throws {
    for request in requests {
      eventCache[request.identifier] = request
    }

    let requestData = try encoder.encode(requests)
    let requestString = String(data: requestData, encoding: .utf8)!

    await eventChannel.send(requestString)
  }

  fileprivate func completeHandshake(_ response: RequestWrapper) async throws {
    try await discharge(response)
  }

  fileprivate func discharge(_ response: RequestWrapper) async throws {
    let originalRequest = eventCache[response.identifier]!

    switch originalRequest {
    case .StartScanning:
      isScanning = true

    case .StopScanning:
      isScanning = false
      try await checkCommandCache()

    default:
      // Most messages don't require any kind of response

      break
    }

    eventCache[response.identifier] = nil
  }

  fileprivate func scan(for seconds: TimeInterval = 30.0) async throws {
    guard
      !isScanning
    else {
      return
    }

    try await send(
      .StartScanning(
        Id: nextEventIndex
      ),
    )

    Task {
      try await Task.sleep(for: .seconds(seconds))

      try await send(
        .StopScanning(
          Id: nextEventIndex
        ),
      )
    }
  }

  func doHandshake() async throws {
    try await send(
      .RequestServerInfo(
        Id: nextEventIndex,
        MessageVersion: 2,
        ClientName: "HapticHelper"
      ),
    )

    try await requestDeviceList()

    try await scan()
  }

  fileprivate func requestDeviceList() async throws {
    try await send(
      .RequestDeviceList(
        Id: nextEventIndex
      ),
    )
  }

}
