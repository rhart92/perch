import Foundation
import Testing
@testable import PerchCore

struct CommandRunnerTests {
    @Test func testCapturesOutputWithoutInterpretingArgumentsAsShell() throws {
        let result = try ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/echo"),
                                              arguments: ["literal; $(not-a-command)"], timeout: 5)
        #expect(result.status == 0)
        #expect(String(decoding: result.output, as: UTF8.self) == "literal; $(not-a-command)\n")
        #expect(result.error.isEmpty)
    }

    @Test func testTimeoutTerminatesProcessAndExplainsFailure() {
        let started = Date()
        do {
            _ = try ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"),
                                        arguments: ["10"], timeout: 0.1)
            Issue.record("Expected command timeout")
        } catch {
            #expect(error.localizedDescription.contains("timed out"))
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func testLaunchFailureNamesExecutable() {
        do {
            _ = try ProcessRunner().run(executable: URL(fileURLWithPath: "/nonexistent/perch-test-command"),
                                        arguments: [], timeout: 1)
            Issue.record("Expected launch failure")
        } catch {
            #expect(error.localizedDescription.contains("perch-test-command"))
        }
    }
}
