import CoreGraphics
import Foundation

struct Bounds: Encodable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct WindowInfo: Encodable {
    let id: Int
    let owner: String
    let name: String
    let layer: Int
    let bounds: Bounds
    let area: Int
}

struct Response: Encodable {
    let count: Int
    let selected: WindowInfo?
    let windows: [WindowInfo]
}

func value(for flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag) else {
        return nil
    }
    let next = CommandLine.arguments.index(after: index)
    guard next < CommandLine.arguments.endIndex else {
        return nil
    }
    return CommandLine.arguments[next]
}

let appFilter = value(for: "--app")?.lowercased()
let nameFilter = value(for: "--window-name")?.lowercased()

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fputs("{\"count\":0,\"windows\":[]}\n", stderr)
    exit(1)
}

var matches: [WindowInfo] = []
matches.reserveCapacity(raw.count)

for entry in raw {
    guard let owner = entry[kCGWindowOwnerName as String] as? String else {
        continue
    }
    if let appFilter, !owner.lowercased().contains(appFilter) {
        continue
    }

    let name = (entry[kCGWindowName as String] as? String) ?? ""
    if let nameFilter, !name.lowercased().contains(nameFilter) {
        continue
    }

    guard let id = entry[kCGWindowNumber as String] as? Int else {
        continue
    }

    let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
    guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any] else {
        continue
    }

    let x = Int((boundsDict["X"] as? Double) ?? 0)
    let y = Int((boundsDict["Y"] as? Double) ?? 0)
    let width = Int((boundsDict["Width"] as? Double) ?? 0)
    let height = Int((boundsDict["Height"] as? Double) ?? 0)
    guard width > 0, height > 0 else {
        continue
    }

    matches.append(
        WindowInfo(
            id: id,
            owner: owner,
            name: name,
            layer: layer,
            bounds: Bounds(x: x, y: y, width: width, height: height),
            area: width * height
        )
    )
}

let ordered = matches.sorted { lhs, rhs in
    let lhsLayerScore = lhs.layer == 0 ? 0 : 1
    let rhsLayerScore = rhs.layer == 0 ? 0 : 1
    if lhsLayerScore != rhsLayerScore {
        return lhsLayerScore < rhsLayerScore
    }
    return lhs.area > rhs.area
}

let response = Response(
    count: ordered.count,
    selected: ordered.first,
    windows: ordered
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

guard let data = try? encoder.encode(response),
      let text = String(data: data, encoding: .utf8) else {
    fputs("{\"count\":\(ordered.count),\"windows\":[]}\n", stderr)
    exit(1)
}

print(text)
