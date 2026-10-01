import XCTest
@testable import eForms

final class AttendanceRulesTests: XCTestCase {
    func testCompletedSessionsAreGreen() {
        let snapshot = AttendanceWidgetSnapshot(
            available: true,
            sessions: [AttendanceWidgetSession(startsAt: Date().addingTimeInterval(-3_600), completed: true)],
            lastUpdated: Date()
        )
        XCTAssertEqual(snapshot.status().0, .green)
        XCTAssertEqual(snapshot.status().1, 0)
    }

    func testFutureSessionMoreThanOneHourAwayIsGreen() {
        let snapshot = AttendanceWidgetSnapshot(
            available: true,
            sessions: [AttendanceWidgetSession(startsAt: Date().addingTimeInterval(3_601), completed: false)],
            lastUpdated: Date()
        )
        XCTAssertEqual(snapshot.status().0, .green)
        XCTAssertEqual(snapshot.status().1, 1)
    }

    func testSessionWithinOneHourIsAmber() {
        let snapshot = AttendanceWidgetSnapshot(
            available: true,
            sessions: [AttendanceWidgetSession(startsAt: Date().addingTimeInterval(3_000), completed: false)],
            lastUpdated: Date()
        )
        XCTAssertEqual(snapshot.status().0, .amber)
    }

    func testIncompletePreviousDayIsRed() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        let snapshot = AttendanceWidgetSnapshot(
            available: true,
            sessions: [AttendanceWidgetSession(startsAt: yesterday, completed: false)],
            lastUpdated: Date()
        )
        XCTAssertEqual(snapshot.status().0, .red)
    }
}

@MainActor
final class StoreParityTests: XCTestCase {
    func testAccountHashNormalizesManchesterEmail() {
        let session = SessionStore.shared
        XCTAssertEqual(session.accountHash("ABC123@manchester.ac.uk"), session.accountHash("abc123"))
        XCTAssertNil(session.accountHash("not a valid username"))
    }

    func testAutomaticRefreshIsThrottledForOneHour() {
        let session = SessionStore.shared
        let now = Date()
        session.recordAutomaticRefresh(at: now)
        XCTAssertFalse(session.automaticRefreshDue(at: now.addingTimeInterval(3_599)))
        XCTAssertTrue(session.automaticRefreshDue(at: now.addingTimeInterval(3_600)))
    }

    func testReviewDemoAttendanceUsesRedOverdueRule() throws {
        let store = AppStore.shared
        try? store.clearAccountData()
        defer { try? store.clearAccountData() }
        try store.startReviewDemo()
        let snapshot = AttendanceRules.build(store: store)
        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(snapshot.level, .red)
        XCTAssertEqual(snapshot.entries.count, 3)
    }

    func testDraftIsSavedBeforeItMovesToOutbox() throws {
        let store = AppStore.shared
        try? store.clearAccountData()
        defer { try? store.clearAccountData() }
        try store.startReviewDemo()
        let formID = try XCTUnwrap(store.forms.first?.string("id"))
        let draftID = store.newDraftID()
        try store.saveDraft(id: draftID, formID: formID, values: ["studentName": "Test Student"],
                            createdAt: nowMilliseconds(), population: nil)
        XCTAssertNotNil(store.draft(id: draftID))
        XCTAssertTrue(store.dirtyDrafts.contains { $0.string("localId") == draftID })
        let rawVault = try XCTUnwrap(SecureVault.shared.rawVaultDataForTests())
        XCTAssertNil(String(data: rawVault, encoding: .utf8)?.range(of: "Test Student"))
        let reloaded = AppStore(vault: .shared)
        XCTAssertEqual(reloaded.draft(id: draftID)?.object("values")?.string("studentName"), "Test Student")

        try store.queueDraft(id: draftID)
        XCTAssertNil(store.draft(id: draftID))
        XCTAssertTrue(store.localOutbox.contains { $0.string("localId") == draftID })
        XCTAssertEqual(store.localOutbox.first?.object("payload")?.string("status"), "outbox")
    }

    func testDeleteAllOnlyRemovesDrafts() throws {
        let store = AppStore.shared
        try? store.clearAccountData()
        defer { try? store.clearAccountData() }
        try store.startReviewDemo()
        let formID = try XCTUnwrap(store.forms.first?.string("id"))
        try store.saveDraft(id: "one", formID: formID, values: [:], createdAt: nowMilliseconds(), population: nil)
        let originalForms = store.forms.count
        XCTAssertEqual(try store.deleteAllDrafts(), 1)
        XCTAssertTrue(store.drafts.isEmpty)
        XCTAssertEqual(store.forms.count, originalForms)
        XCTAssertTrue(store.outbox.isEmpty)
        XCTAssertTrue(store.sent.isEmpty)
    }

    func testAttendanceOutboxMatchesSelectedPopulation() throws {
        let store = AppStore.shared
        try? store.clearAccountData()
        defer { try? store.clearAccountData() }
        try store.startReviewDemo()
        let form = try XCTUnwrap(store.forms.first)
        let set = try XCTUnwrap(form.objects("populationSets").first)
        var population = try XCTUnwrap(set.objects("populations").dropFirst().first)
        population["setId"] = set["id"]
        population["setName"] = set.string("name")
        try store.saveDraft(id: "attendance", formID: form.string("id"), values: [:],
                            createdAt: nowMilliseconds(), population: population)
        try store.queueDraft(id: "attendance")

        let snapshot = AttendanceRules.build(store: store)
        let matched = try XCTUnwrap(snapshot.entries.first { $0.populationID == population.string("id") })
        XCTAssertTrue(matched.completed)
        XCTAssertEqual(matched.outboxID, "attendance")
    }
}
