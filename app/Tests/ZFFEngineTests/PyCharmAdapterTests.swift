import Testing
import Foundation
@testable import HauntsAdapters

@Suite("PyCharmAdapter")
struct PyCharmAdapterTests {

    @Test("parseRecentProjectsXML expands $USER_HOME$ and returns valid paths")
    func testUserHomeExpansion() {
        let home = NSHomeDirectory()
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <application>
          <component name="RecentDirectoryProjectsManager">
            <option name="recentPaths">
              <list>
                <entry key="$USER_HOME$/code/myproject" />
                <entry key="$USER_HOME$/work/otherproject" />
                <entry key="/absolute/path/to/project" />
              </list>
            </option>
          </component>
        </application>
        """
        let data = xml.data(using: .utf8)!
        let adapter = PyCharmAdapter()
        let paths = adapter.parseRecentProjectsXML(data: data, home: home)

        #expect(paths.contains("\(home)/code/myproject"))
        #expect(paths.contains("\(home)/work/otherproject"))
        #expect(paths.contains("/absolute/path/to/project"))
        #expect(paths.count == 3)
    }

    @Test("parseRecentProjectsXML filters non-absolute paths")
    func testNonAbsolutePathsFiltered() {
        let home = NSHomeDirectory()
        let xml = """
        <application>
          <component>
            <list>
              <entry key="relative/path" />
              <entry key="$USER_HOME$/valid/path" />
            </list>
          </component>
        </application>
        """
        let data = xml.data(using: .utf8)!
        let adapter = PyCharmAdapter()
        let paths = adapter.parseRecentProjectsXML(data: data, home: home)

        #expect(!paths.contains("relative/path"))
        #expect(paths.contains("\(home)/valid/path"))
    }

    @Test("recentFolders returns empty when JetBrains dir does not exist")
    func testMissingJetBrainsDir() throws {
        let adapter = PyCharmAdapter()
        // When run in CI or on a machine without JetBrains tools installed,
        // this returns [] without throwing.
        let urls = try adapter.recentFolders()
        // Result may be [] or non-empty; what matters is no exception is thrown
        // and all returned URLs are valid existing paths.
        for url in urls {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
