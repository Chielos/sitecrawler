import SwiftUI

/// Placeholder views for features implemented in V1.

struct ExportsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up.circle")
                .font(.system(size: 48)).foregroundStyle(.blue)
            Text("Exports").font(.title2.weight(.semibold))
            Text("Use the toolbar Export menu to generate CSV, JSON, and sitemap exports.\n\nBatch export scheduling is a V1 feature.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Exports")
    }
}

struct SchedulesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48)).foregroundStyle(.blue)
            Text("Schedules").font(.title2.weight(.semibold))
            Text("Recurring crawl scheduling is planned for V1.\nYou will be able to configure daily, weekly, and monthly automated crawls with automatic export delivery.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            // TODO: implement Schedule list + creation sheet
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Schedules")
    }
}
