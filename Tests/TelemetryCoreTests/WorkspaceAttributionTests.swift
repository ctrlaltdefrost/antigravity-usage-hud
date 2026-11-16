import XCTest
@testable import TelemetryCore

final class WorkspaceAttributionTests: XCTestCase {

    func testPercentEncodedFileURLDecoding() {
        let rawJSON = #"["file:///workspace/demo/Sample%20Project/"]"#
        let ws = SQLiteSummaryReader.decodeWorkspaceUris(rawJSON)

        XCTAssertEqual(ws.name, "Sample Project")
        XCTAssertEqual(ws.workspacePath, "/workspace/demo/Sample Project")
        XCTAssertEqual(ws.id, "/workspace/demo/Sample Project")
    }

    func testPlainPathInJSONArray() {
        let rawJSON = #"["/workspace/projects/NeuralEngine"]"#
        let ws = SQLiteSummaryReader.decodeWorkspaceUris(rawJSON)

        XCTAssertEqual(ws.name, "NeuralEngine")
        XCTAssertEqual(ws.workspacePath, "/workspace/projects/NeuralEngine")
    }

    func testSingleUnquotedURI() {
        let rawURI = "file:///workspace/dev/AntigravityHUD"
        let ws = SQLiteSummaryReader.decodeWorkspaceUris(rawURI)

        XCTAssertEqual(ws.name, "AntigravityHUD")
        XCTAssertEqual(ws.workspacePath, "/workspace/dev/AntigravityHUD")
    }

    func testMultipleURIsSelectsFirstNonEmpty() {
        let rawJSON = #"["", "file:///workspace/projects/Apollo%2011", "file:///workspace/projects/Gemini"]"#
        let ws = SQLiteSummaryReader.decodeWorkspaceUris(rawJSON)

        XCTAssertEqual(ws.name, "Apollo 11")
        XCTAssertEqual(ws.workspacePath, "/workspace/projects/Apollo 11")
    }

    func testEmptyAndMalformedFallbacksToUnassigned() {
        let empty1 = SQLiteSummaryReader.decodeWorkspaceUris("")
        XCTAssertEqual(empty1, .unassigned)
        XCTAssertEqual(empty1.name, "General / Unassigned")

        let emptyArray = SQLiteSummaryReader.decodeWorkspaceUris("[]")
        XCTAssertEqual(emptyArray, .unassigned)

        let spacesOnly = SQLiteSummaryReader.decodeWorkspaceUris("   ")
        XCTAssertEqual(spacesOnly, .unassigned)

        let rootSlash = SQLiteSummaryReader.decodeWorkspaceUris(#"["/"]"#)
        XCTAssertEqual(rootSlash, .unassigned)

        let fileRoot = SQLiteSummaryReader.decodeWorkspaceUris(#"["file:///"]"#)
        XCTAssertEqual(fileRoot, .unassigned)
    }

    func testTrailingSlashRemovedCleanly() {
        let rawJSON = #"["file:///workspace/projects/CoreLib////"]"#
        let ws = SQLiteSummaryReader.decodeWorkspaceUris(rawJSON)

        XCTAssertEqual(ws.name, "CoreLib")
        XCTAssertEqual(ws.workspacePath, "/workspace/projects/CoreLib")
    }
}
