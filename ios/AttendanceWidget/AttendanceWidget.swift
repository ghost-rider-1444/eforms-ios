import SwiftUI
import WidgetKit

struct AttendanceTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: AttendanceWidgetSnapshot
}

struct AttendanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> AttendanceTimelineEntry {
        AttendanceTimelineEntry(date: Date(), snapshot: AttendanceWidgetSnapshot(
            available: true,
            sessions: [AttendanceWidgetSession(startsAt: Date().addingTimeInterval(1_800), completed: false)],
            lastUpdated: Date()
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (AttendanceTimelineEntry) -> Void) {
        completion(AttendanceTimelineEntry(date: Date(), snapshot: AttendanceWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AttendanceTimelineEntry>) -> Void) {
        let now = Date()
        let snapshot = AttendanceWidgetSnapshot.load()
        let entry = AttendanceTimelineEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3_600))))
    }
}

struct AttendanceWidgetView: View {
    let entry: AttendanceTimelineEntry

    private var status: (level: AttendanceLevel, count: Int) { entry.snapshot.status(at: entry.date) }
    private var title: String {
        guard entry.snapshot.available else { return "Attendance" }
        switch status.level {
        case .red: return "Attendance overdue"
        case .amber: return "Attendance due soon"
        case .green: return status.count == 0 ? "Attendance complete" : "Attendance up to date"
        }
    }
    private var background: Color {
        guard entry.snapshot.available else { return Color(red: 242/255, green: 239/255, blue: 243/255) }
        switch status.level {
        case .green: return Color(red: 220/255, green: 245/255, blue: 231/255)
        case .amber: return Color(red: 1, green: 241/255, blue: 199/255)
        case .red: return Color(red: 1, green: 226/255, blue: 226/255)
        }
    }
    private var foreground: Color {
        guard entry.snapshot.available else { return Color(red: 79/255, green: 72/255, blue: 81/255) }
        switch status.level {
        case .green: return Color(red: 20/255, green: 94/255, blue: 59/255)
        case .amber: return Color(red: 104/255, green: 70/255, blue: 0)
        case .red: return Color(red: 132/255, green: 25/255, blue: 25/255)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("●").font(.title2)
                Text("eForms").font(.caption)
                Spacer()
            }
            Text(title).font(.headline).lineLimit(2)
            Text(entry.snapshot.available ? "Tap to view sessions" : "Open eForms to download attendance forms")
                .font(.caption2).lineLimit(2)
            Spacer(minLength: 0)
            if entry.snapshot.lastUpdated != .distantPast {
                Text("Updated \(entry.snapshot.lastUpdated, style: .time)").font(.caption2).opacity(0.75)
            }
        }
        .foregroundStyle(foreground)
        .containerBackground(background, for: .widget)
        .widgetURL(URL(string: "eforms://attendance"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

@main
struct AttendanceWidget: Widget {
    let kind = "AttendanceWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AttendanceProvider()) { entry in
            AttendanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Attendance sessions")
        .description("Shows whether attendance is up to date, due soon or overdue.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
