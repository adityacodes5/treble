import SwiftUI
import TrebleCore

// MARK: - Tile

struct KeepAwakeTile: View {
    let controller: KeepAwakeController
    @State private var pickingTime = false
    @State private var untilTime = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickChoices
            if pickingTime {
                timePicker
            }
            if let error = controller.startError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { controller.toggle() } label: {
                TileToggleIcon(controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer", isOn: controller.isActive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isActive ? "Turn off Keep Awake" : "Turn on Keep Awake")

            VStack(alignment: .leading, spacing: 1) {
                Text("Keep Awake")
                    .font(.headline)
                // Re-renders once a minute, and only while the tile is on screen.
                TimelineView(.everyMinute) { timeline in
                    StatusLine(controller: controller, now: timeline.date)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button("Until a Time…") { pickingTime = true }
                Menu("While an App Is Running") {
                    let apps = WatchedApp.running()
                    if apps.isEmpty {
                        Text("No apps open")
                    }
                    ForEach(apps, id: \.pid) { app in
                        Button(app.name) { controller.start(.whileRunning(app)) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More options")
        }
    }

    private var quickChoices: some View {
        HStack(spacing: 6) {
            ForEach(KeepAwakeMode.quickDurations, id: \.self) { seconds in
                ChoiceChip(
                    title: Format.choice(seconds),
                    isSelected: controller.session?.mode == .duration(seconds)
                ) {
                    controller.start(.duration(seconds))
                }
            }
            ChoiceChip(title: "∞", isSelected: controller.session?.mode == .indefinitely) {
                controller.start(.indefinitely)
            }
            .accessibilityLabel("Indefinitely")
        }
    }

    private var timePicker: some View {
        HStack(spacing: 8) {
            Text("Until")
                .font(.callout)
            DatePicker("Until", selection: $untilTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
            Spacer(minLength: 0)
            Button("Cancel") { pickingTime = false }
                .controlSize(.small)
            Button("Start") {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: untilTime)
                let end = Calendar.current.nextOccurrence(hour: parts.hour ?? 0, minute: parts.minute ?? 0, after: Date())
                controller.start(.until(end))
                pickingTime = false
            }
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct StatusLine: View {
    let controller: KeepAwakeController
    let now: Date

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .lineLimit(1)
    }

    private var text: String {
        guard let session = controller.session else {
            return controller.endNote ?? "Off"
        }
        switch session.mode {
        case .duration, .until:
            guard let end = session.endDate else { return "On" }
            return "Until \(Format.time(end)) · \(Format.remaining(end.timeIntervalSince(now))) left"
        case .whileRunning(let app):
            return "While \(app.name) is running"
        case .indefinitely:
            let elapsed = now.timeIntervalSince(session.startedAt)
            return elapsed >= 60 ? "Indefinitely · on for \(Format.remaining(elapsed))" : "Indefinitely"
        }
    }

    /// A gentle reminder after 8 hours, so an indefinite session isn't forgotten for days.
    private var isWarning: Bool {
        guard let session = controller.session, session.mode == .indefinitely else { return false }
        return now.timeIntervalSince(session.startedAt) >= 8 * 3600
    }
}

private struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

struct KeepAwakeSettings: View {
    @Bindable var preferences: KeepAwakePreferences

    var body: some View {
        Form {
            Section {
                Picker("Clicking the cup keeps awake for", selection: $preferences.defaultDuration) {
                    ForEach(KeepAwakeMode.quickDurations, id: \.self) { seconds in
                        Text(Format.remaining(seconds)).tag(seconds)
                    }
                    Text("Indefinitely").tag(TimeInterval(0))
                }
            }

            Section {
                Toggle("Keep the display on too", isOn: $preferences.keepDisplayOn)
            } footer: {
                Text("When off, your screen can turn off while your Mac keeps working. This saves battery.")
            }

            Section("Battery") {
                Toggle("Stop when battery is low", isOn: $preferences.stopOnLowBattery)
                if preferences.stopOnLowBattery {
                    Picker("Low means below", selection: $preferences.lowBatteryThreshold) {
                        ForEach(KeepAwakePreferences.thresholdChoices, id: \.self) { percent in
                            Text("\(percent)%").tag(percent)
                        }
                    }
                }
                Toggle("Only while plugged in", isOn: $preferences.onlyWhilePluggedIn)
            }

            Section("Menu bar") {
                Toggle("Show time left next to the icon", isOn: $preferences.showTimeInMenuBar)
            }

            Section {
                Label {
                    Text("With the lid closed, macOS sleeps anyway, unless your Mac is plugged in and connected to an external display. Staying awake with the lid closed on battery is planned for a later version.")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
