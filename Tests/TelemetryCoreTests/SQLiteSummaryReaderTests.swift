import XCTest
import SQLite3
@testable import TelemetryCore

final class SQLiteSummaryReaderTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryCoreTests_SQLite_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testReadSummariesFromSQLiteDatabase() throws {
        let dbPath = tempDirectory.appendingPathComponent("test_summaries.db").path

        // Create and populate test SQLite database
        var db: OpaquePointer?
        let openRes = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        XCTAssertEqual(openRes, SQLITE_OK)
        guard let db else {
            XCTFail("Failed to create SQLite db")
            return
        }

        let createTableSQL = """
        CREATE TABLE conversation_summaries (
            conversation_id TEXT PRIMARY KEY,
            title TEXT,
            step_count INTEGER,
            last_modified_time TEXT,
            workspace_uris TEXT,
            status TEXT,
            source TEXT,
            parent_conversation_id TEXT,
            nesting_depth INTEGER,
            not_fully_idle INTEGER,
            killed INTEGER
        );
        """
        XCTAssertEqual(sqlite3_exec(db, createTableSQL, nil, nil, nil), SQLITE_OK)

        // Insert record 1: Running coordinator in project "NeuralSim"
        let insertSQL1 = """
        INSERT INTO conversation_summaries VALUES (
            'conv-coord-1',
            'Architecture Simulation',
            42,
            '2026-11-15T19:30:00Z',
            '["file:///workspace/projects/NeuralSim"]',
            'CASCADE_RUN_STATUS_RUNNING',
            'Desktop',
            NULL,
            0,
            1,
            0
        );
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL1, nil, nil, nil), SQLITE_OK)

        // Insert record 2: Subagent worker in "NeuralSim"
        let insertSQL2 = """
        INSERT INTO conversation_summaries VALUES (
            'conv-subagent-2',
            'Matrix Optimizer Helper',
            15,
            '2026-11-15T19:31:00Z',
            '["file:///workspace/projects/NeuralSim"]',
            'CASCADE_RUN_STATUS_RUNNING',
            'Desktop',
            'conv-coord-1',
            1,
            1,
            0
        );
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL2, nil, nil, nil), SQLITE_OK)

        // Insert record 3: Killed idle session
        let insertSQL3 = """
        INSERT INTO conversation_summaries VALUES (
            'conv-killed-3',
            'Old Session',
            5,
            '2026-11-15T18:00:00Z',
            '[]',
            'CASCADE_RUN_STATUS_IDLE',
            'CLI',
            NULL,
            0,
            0,
            1
        );
        """
        XCTAssertEqual(sqlite3_exec(db, insertSQL3, nil, nil, nil), SQLITE_OK)

        sqlite3_close(db)

        // Use SQLiteSummaryReader to read the database
        let records = SQLiteSummaryReader.readSummaries(fromDatabaseAt: dbPath, defaultSource: "Desktop")
        XCTAssertEqual(records.count, 3)

        let coord = records.first { $0.conversationId == "conv-coord-1" }
        XCTAssertNotNil(coord)
        XCTAssertEqual(coord?.title, "Architecture Simulation")
        XCTAssertEqual(coord?.projectName, "NeuralSim")
        XCTAssertEqual(coord?.stepCount, 42)
        XCTAssertTrue(coord?.isRunning == true)
        XCTAssertFalse(coord?.isSubagent == true)

        let sub = records.first { $0.conversationId == "conv-subagent-2" }
        XCTAssertNotNil(sub)
        XCTAssertEqual(sub?.title, "Matrix Optimizer Helper")
        XCTAssertTrue(sub?.isRunning == true)
        XCTAssertTrue(sub?.isSubagent == true)
        XCTAssertEqual(sub?.parentConversationId, "conv-coord-1")

        let killed = records.first { $0.conversationId == "conv-killed-3" }
        XCTAssertNotNil(killed)
        XCTAssertFalse(killed?.isRunning == true, "Killed session must not be running")
        XCTAssertTrue(killed?.killed == true)
        XCTAssertEqual(killed?.projectName, "General / Unassigned")
    }

    func testMissingDatabaseReturnsEmptyList() {
        let nonExistentPath = "/tmp/non_existent_antigravity_db_\(UUID().uuidString).db"
        let records = SQLiteSummaryReader.readSummaries(fromDatabaseAt: nonExistentPath)
        XCTAssertTrue(records.isEmpty)
    }
}
