import SwiftUI

/// Treble's standard tile look, close to Control Center's tiles.
/// The panel applies it around every feature's tile; features don't need to.
public struct TileBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

public extension View {
    func trebleTile() -> some View {
        modifier(TileBackground())
    }
}

/// A round icon button like Control Center's toggles: filled with the accent color when on.
public struct TileToggleIcon: View {
    private let symbol: String
    private let isOn: Bool

    public init(_ symbol: String, isOn: Bool) {
        self.symbol = symbol
        self.isOn = isOn
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 28, height: 28)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Circle())
    }
}
