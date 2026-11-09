import Observation
import SwiftUI

/// A named spot in Treble's UI where any feature can add a small piece of UI.
///
/// This is how features cooperate without knowing about each other: for
/// example, Sleep Timer adds a "Sleep after this track" button to the Now
/// Playing popover's accessory slot, and Now Playing just draws whatever is there.
public struct SlotID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Bottom row of the main panel, next to the Settings button.
    public static let panelFooter = SlotID(rawValue: "panel.footer")
    /// Below the controls in the Now Playing popover.
    public static let nowPlayingAccessory = SlotID(rawValue: "nowPlaying.popover.accessory")
}

public struct SlotContribution: Identifiable {
    public let id: UUID
    public let moduleID: String
    public let view: AnyView
}

/// Holds every feature's slot contributions.
@MainActor
@Observable
public final class SlotRegistry {
    public private(set) var contributions: [SlotID: [SlotContribution]] = [:]

    public init() {}

    public func contributions(for slot: SlotID) -> [SlotContribution] {
        contributions[slot] ?? []
    }

    func add(_ view: AnyView, to slot: SlotID, from moduleID: String) -> UUID {
        let contribution = SlotContribution(id: UUID(), moduleID: moduleID, view: view)
        contributions[slot, default: []].append(contribution)
        return contribution.id
    }

    func remove(_ id: UUID) {
        for (slot, list) in contributions {
            let remaining = list.filter { $0.id != id }
            if remaining.count != list.count {
                contributions[slot] = remaining.isEmpty ? nil : remaining
            }
        }
    }

    /// Total number of contributions. Used by tests to check nothing leaks.
    var contributionCount: Int {
        contributions.values.reduce(0) { $0 + $1.count }
    }
}

/// Draws everything contributed to a slot. Wrap it in an HStack or VStack as needed.
public struct SlotView: View {
    private let slot: SlotID
    private let registry: SlotRegistry

    public init(_ slot: SlotID, registry: SlotRegistry) {
        self.slot = slot
        self.registry = registry
    }

    public var body: some View {
        ForEach(registry.contributions(for: slot)) { contribution in
            contribution.view
        }
    }
}
