import Foundation

enum FixtureBundleLoader {
    static func load(from url: URL) throws -> FixtureBundle {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureBundle.self, from: data)
    }
}
