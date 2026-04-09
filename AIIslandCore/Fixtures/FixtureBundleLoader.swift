import Foundation

public enum FixtureBundleLoader {
    public static func load(from url: URL) throws -> FixtureBundle {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureBundle.self, from: data)
    }
}

public final class FixtureBundleMarker: NSObject {
    public static let bundle = Bundle(for: FixtureBundleMarker.self)
}
