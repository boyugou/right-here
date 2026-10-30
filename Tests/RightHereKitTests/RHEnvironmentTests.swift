import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("The variables that move Right Here's files")
struct RHEnvironmentTests {
    @Test func aVariableSetToNothingIsAProblemThatNamesItAndSaysWhatToDo() throws {
        for name in RHEnvironment.names {
            let text = try #require(RHEnvironment.problem(in: [name: "", "PATH": "/usr/bin"]), "\(name)")
            #expect(text.hasPrefix("\(name) is set to nothing."), "\(text)")
            #expect(text.contains("RH_HOME=/tmp/trial rh setup"), "\(text)")
        }
        let two = try #require(RHEnvironment.problem(in: ["RH_HOME": "", "RH_LOG_DIR": ""]))
        #expect(two.hasPrefix("RH_HOME and RH_LOG_DIR are set to nothing."), "\(two)")
    }

    @Test func aVariableThatIsNotSetOrNamesAPathIsNoProblem() {
        #expect(RHEnvironment.problem(in: [:]) == nil)
        #expect(RHEnvironment.problem(in: ["RH_HOME": "/tmp/trial", "RH_CONFIG": "/tmp/c.toml", "RH_CONFIG_DIR": "/tmp/c", "RH_LOG_DIR": "/tmp/l"]) == nil)
        // Not Right Here's, and the XDG specification reads an empty one as not set.
        #expect(RHEnvironment.problem(in: ["XDG_CONFIG_HOME": ""]) == nil)
    }

    @Test func aVariableSetToNothingIsNotTheRealFolderAndNothingCanBeMadeThere() throws {
        let real = FileManager.default.temporaryDirectory.appendingPathComponent("rh-env-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: real) }
        #expect(RHEnvironment.path("RH_HOME", in: [:]) == nil)
        #expect(RHEnvironment.path("RH_HOME", in: ["RH_HOME": "~/trial"])?.path == (("~/trial" as NSString).expandingTildeInPath))
        let nowhere = try #require(RHEnvironment.path("RH_HOME", in: ["RH_HOME": ""]))
        #expect(nowhere.path.hasPrefix("/dev/null/"), "\(nowhere.path)")
        #expect(throws: (any Error).self) { try FileManager.default.createDirectory(at: nowhere.appendingPathComponent("x"), withIntermediateDirectories: true) }
        #expect(LiveSystemFacts.homeOverride(in: ["RH_HOME": ""])?.path.hasPrefix("/dev/null/") == true)
    }

    @Test func theConfigAndTheLogDoNotFallBackToTheHomeWhenTheirVariableIsSetToNothing() throws {
        let home = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: home) }
        for name in ["RH_CONFIG", "RH_CONFIG_DIR"] {
            let paths = RHPaths(environment: [name: ""], home: home)
            #expect(paths.configFile.path.hasPrefix("/dev/null"), "\(name): \(paths.configFile.path)")
            #expect(throws: (any Error).self) { try ConfigStore.initialize(paths: paths, detected: DetectedEnvironment(terminal: "terminal")) }
        }
        #expect(RHPaths(environment: ["RH_LOG_DIR": ""], home: home).logDirectory.path.hasPrefix("/dev/null/"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty, "something was written in the home")
    }

    @Test func anEmptyXDGVariableIsNotSetAsTheSpecificationSays() throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let paths = RHPaths(environment: ["XDG_CONFIG_HOME": ""], home: home)
        #expect(paths.configFile.path == "/Users/tester/.config/right-here/config.toml")
    }
}
