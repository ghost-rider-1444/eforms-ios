import Foundation

struct AttendanceEntry: Identifiable {
    let formID: String
    let formName: String
    let populationID: String
    let populationSetID: String
    let populationName: String
    let populationSetName: String
    let title: String
    let startsAt: Date
    var completed = false
    var sentUUID = ""
    var outboxID = ""
    var draftID = ""
    var id: String { "\(formID):\(populationSetID):\(populationID)" }
}

struct AttendanceSnapshot {
    let available: Bool
    let entries: [AttendanceEntry]
    let level: AttendanceLevel
    let incompleteCount: Int
}

@MainActor
enum AttendanceRules {
    static func build(store: AppStore, now: Date = Date()) -> AttendanceSnapshot {
        var available = false
        var entries: [AttendanceEntry] = []
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_GB")
        input.calendar = Calendar(identifier: .gregorian)
        input.dateFormat = "dd-MM-yyyy_HH-mm"

        for form in store.forms {
            let identity = "\(form.string("name")) \(form.string("workspaceName"))".lowercased()
            if identity.contains("attendance") { available = true }
            for set in form.objects("populationSets") {
                for population in set.objects("populations") {
                    let name = population.string("name").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard name.count > 17, name[name.index(name.startIndex, offsetBy: 16)] == "_" else { continue }
                    let datePart = String(name.prefix(16))
                    guard let startsAt = input.date(from: datePart) else { continue }
                    let title = String(name.dropFirst(17)).trimmingCharacters(in: .whitespacesAndNewlines)
                    available = true
                    entries.append(AttendanceEntry(
                        formID: form.string("id"), formName: form.string("name", default: "Attendance form"),
                        populationID: population.string("id"), populationSetID: set.string("id"),
                        populationName: name, populationSetName: set.string("name"),
                        title: title, startsAt: startsAt
                    ))
                }
            }
        }

        entries.sort { $0.startsAt < $1.startsAt }
        let sent = store.sent
        let outbox = store.outbox
        let drafts = store.drafts
        for index in entries.indices {
            for header in sent {
                let uuid = header.string("uuid")
                if matches(entries[index], store.sentSubmission(uuid: uuid)) || matches(entries[index], header) {
                    entries[index].completed = true
                    entries[index].sentUUID = uuid
                    break
                }
            }
            if !entries[index].completed {
                for header in outbox {
                    let id = header.string("localId").isEmpty ? header.string("uuid") : header.string("localId")
                    if matches(entries[index], store.outboxSubmission(id: id)) || matches(entries[index], header) {
                        entries[index].completed = true
                        entries[index].outboxID = id
                        break
                    }
                }
            }
            if let draft = drafts.first(where: { matches(entries[index], $0) }) {
                entries[index].draftID = draft.string("localId")
            }
        }

        let incomplete = entries.filter { !$0.completed }
        let startOfToday = Calendar.current.startOfDay(for: now)
        let stale = incomplete.contains { $0.startsAt < startOfToday }
        let dueSoon = incomplete.contains { $0.startsAt <= now.addingTimeInterval(3_600) }
        let level: AttendanceLevel = incomplete.isEmpty ? .green : stale ? .red : dueSoon ? .amber : .green
        return AttendanceSnapshot(available: available, entries: entries, level: level,
                                  incompleteCount: incomplete.count)
    }

    private static func matches(_ entry: AttendanceEntry, _ submission: JSONObject?) -> Bool {
        guard let submission else { return false }
        let formID = submission.string("formId")
        if !formID.isEmpty && formID != entry.formID { return false }
        if let population = submission.object("populationSnapshot") {
            let id = population.string("id")
            if !id.isEmpty && id == entry.populationID { return true }
            return same(entry.populationName, population.string("name")) &&
                (population.string("setName").isEmpty || same(entry.populationSetName, population.string("setName")))
        }
        return same(entry.populationName, submission.string("populationName")) &&
            (submission.string("populationSetName").isEmpty || same(entry.populationSetName, submission.string("populationSetName")))
    }

    private static func same(_ left: String, _ right: String) -> Bool {
        !left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        left.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(right.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
