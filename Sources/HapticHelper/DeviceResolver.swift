// Copyright (c) 2026 Lexie T
// Licensed under the terms of GPL v3.0 or later, see LICENSE

import Foundation

class DeviceResolver {
  struct DeviceRule {
    let from: RuleName
    let to: Resolution

    func match(_ query: any StringProtocol) -> Resolution? {
      switch from {
      case .any:
        to

      case .name(let name):
        if name == query {
          to
        } else {
          nil
        }

      case .index(let number):
        if
          let query = Int(query),
          query == number
        {
          to
        } else {
          nil
        }
      }
    }

    init(from: RuleName, to: Resolution) {
      self.from = from
      self.to = to
    }

    init?(_ string: any StringProtocol) {
      let elements = string.split(separator: " ")

      guard
        elements.count == 2
      else {
        return nil
      }

      let fromName = String(elements.first!)
      let toName = String(elements.last!)

      if let from = RuleName(string: fromName) {
        self.from = from
      } else {
        return nil
      }

      if let to = Resolution(string: toName) {
        self.to = to
      } else {
        return nil
      }
    }
  }

  let rules: [DeviceRule]

  init() {
    rules = []
  }

  enum RuleName: Equatable {
    case any
    case name(String)
    case index(Int)

    init?(string: String) {
      if string == "*" {
        self = .any
      } else if let index = Int(string) {
        self = .index(index)
      } else if string.contains(/^[_a-z][_a-z-]*$/) {
        self = .name(string)
      } else {
        return nil
      }
    }
  }

  enum Resolution {
    case first
    case index(Int)

    init?(string: String) {
      if string == "@1" {
        self = .first
      } else if let index = Int(string) {
        self = .index(index)
      } else {
        return nil
      }
    }
  }

  func resolve(device: any StringProtocol) -> Resolution? {
    let matches = rules
      .compactMap { rule in
        rule.match(device)
      }

    if matches.count == 0 {
      if let directResolution = Resolution(string: String(device)) {
        return directResolution
      } else {
        return nil
      }
    } else if matches.count == 1 {
      return matches.first
    } else {
      let narrowedMatches = rules
        .filter { rule in
          rule.from != .any
        }
        .compactMap { rule in
          rule.match(device)
        }

      if (narrowedMatches.count == 1) {
        return narrowedMatches.first
      } else {
        print("?? Ambiguous device name \(device) matches multiple rules, sending first match")

        return narrowedMatches.first ?? matches.first
      }
    }
  }
}
