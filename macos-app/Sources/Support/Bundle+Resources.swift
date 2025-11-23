import Foundation

extension Bundle {
    static let appResources: Bundle = {
        let bundleName = "AutoBrowsingApp_AutoBrowsingApp"
        let filename = "\(bundleName).bundle"
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? Bundle.main.bundlePath)
        var searchPaths: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            searchPaths.append(resourceURL)
        }

        let bundleURL = Bundle.main.bundleURL
        searchPaths.append(bundleURL)
        searchPaths.append(bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
        searchPaths.append(bundleURL.deletingLastPathComponent())

        let executableDir = executableURL.deletingLastPathComponent()
        searchPaths.append(executableDir)
        searchPaths.append(executableDir.deletingLastPathComponent())
        searchPaths.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

        for candidate in searchPaths {
            let bundleURL = candidate.appendingPathComponent(filename, isDirectory: true)
            if let bundle = Bundle(url: bundleURL) {
                return bundle
            }
        }

        fatalError("could not locate \(filename) in: \(searchPaths)")
    }()
}
