import SwiftUI

struct AttendanceSessionsView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: AttendanceSnapshot
    let selected: (AttendanceEntry) -> Void

    var body: some View {
        NavigationStack {
            List {
                if snapshot.entries.isEmpty { Text("No attendance sessions are currently open.") }
                ForEach(snapshot.entries) { entry in
                    Button {
                        dismiss()
                        selected(entry)
                    } label: {
                        HStack(spacing: 10) {
                            Text(entry.completed ? "✓" : entry.startsAt < Date() ? "✕" : "")
                                .font(.title3).foregroundStyle(entry.completed ? .green : .red)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.startsAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(AppTheme.muted)
                                Text(entry.title).font(.subheadline).foregroundStyle(AppTheme.ink)
                            }
                            Spacer(); Text("›").font(.title3).foregroundStyle(AppTheme.purple)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Attendance sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
