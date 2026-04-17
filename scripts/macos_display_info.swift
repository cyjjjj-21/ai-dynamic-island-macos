import AppKit
import Foundation

struct DisplayInfo: Encodable {
    let frameX: Double
    let frameY: Double
    let widthPoints: Double
    let heightPoints: Double
    let scale: Double
    let isMain: Bool
}

struct Response: Encodable {
    let count: Int
    let displays: [DisplayInfo]
}

let displays = NSScreen.screens.map { screen in
    DisplayInfo(
        frameX: screen.frame.origin.x,
        frameY: screen.frame.origin.y,
        widthPoints: screen.frame.width,
        heightPoints: screen.frame.height,
        scale: screen.backingScaleFactor,
        isMain: screen == NSScreen.main
    )
}

let response = Response(count: displays.count, displays: displays)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

guard let data = try? encoder.encode(response),
      let text = String(data: data, encoding: .utf8) else {
    fputs("{\"count\":0,\"displays\":[]}\n", stderr)
    exit(1)
}

print(text)
