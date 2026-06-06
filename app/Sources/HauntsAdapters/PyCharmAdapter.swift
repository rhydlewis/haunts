import Foundation

public struct PyCharmAdapter: EditorAdapter {
    public var editorName: String { "PyCharm" }

    public init() {}

    public func recentFolders() throws -> [URL] {
        let home = NSHomeDirectory()
        let jetbrainsBase = "\(home)/Library/Application Support/JetBrains"
        let fm = FileManager.default

        guard fm.fileExists(atPath: jetbrainsBase) else { return [] }

        let productDirs: [String]
        do {
            productDirs = try fm.contentsOfDirectory(atPath: jetbrainsBase)
        } catch {
            return []
        }

        var result: [URL] = []
        for product in productDirs {
            let xmlPath = "\(jetbrainsBase)/\(product)/options/recentProjects.xml"
            guard fm.fileExists(atPath: xmlPath),
                  let data = fm.contents(atPath: xmlPath) else { continue }
            let paths = parseRecentProjectsXML(data: data, home: home)
            for path in paths {
                let url = URL(fileURLWithPath: path)
                if fm.fileExists(atPath: path) {
                    result.append(url)
                }
            }
        }
        return result
    }

    func parseRecentProjectsXML(data: Data, home: String) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var paths: [String] = []
        // Match <entry key="$USER_HOME$/..." /> or <entry key="/absolute/path" />
        // The key attribute contains the project path
        let pattern = #"<entry\s+key="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: range)
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: xml) else { continue }
            var path = String(xml[keyRange])
            path = path.replacingOccurrences(of: "$USER_HOME$", with: home)
            if path.hasPrefix("/") {
                paths.append(path)
            }
        }
        return paths
    }
}
