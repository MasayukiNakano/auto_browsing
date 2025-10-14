import Foundation

enum SiteProfileLoaderError: Error {
    case resourceNotFound
}

struct SiteProfileLoader {
    private let decoder = JSONDecoder()

    func loadProfiles() throws -> [SiteProfile] {
        guard let url = Bundle.module.url(forResource: "sites", withExtension: "json") else {
            throw SiteProfileLoaderError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([SiteProfile].self, from: data)
    }
}
