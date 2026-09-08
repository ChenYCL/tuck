import SwiftUI

/// Segmented control for the menu bar's shape, with an interactive preview for
/// choosing each end's cap style.
struct ShapePicker: View {
    @Binding var config: AppearanceConfiguration

    private let barWidth: CGFloat = 300
    private let barHeight: CGFloat = 24
    private let splitSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Shape", selection: $config.shapeKind) {
                Text("None").tag(MenuBarShapeKind.none)
                Text("Full").tag(MenuBarShapeKind.full)
                Text("Split").tag(MenuBarShapeKind.split)
            }
            .pickerStyle(.segmented)

            switch config.shapeKind {
            case .none:
                EmptyView()
            case .full:
                fullPreview
            case .split:
                splitPreview
            }
        }
    }

    private var fullPreview: some View {
        shapeBar(leading: config.fullShapeInfo.leadingEndCap, trailing: config.fullShapeInfo.trailingEndCap)
            .frame(width: barWidth, height: barHeight)
            .overlay(alignment: .leading) {
                endCapMenu($config.fullShapeInfo.leadingEndCap)
            }
            .overlay(alignment: .trailing) {
                endCapMenu($config.fullShapeInfo.trailingEndCap)
            }
    }

    private var splitPreview: some View {
        HStack(spacing: splitSpacing) {
            splitBar(
                leadingCap: $config.splitShapeInfo.leading.leadingEndCap,
                trailingCap: $config.splitShapeInfo.leading.trailingEndCap,
                width: (barWidth - splitSpacing) * 0.4
            )
            splitBar(
                leadingCap: $config.splitShapeInfo.trailing.leadingEndCap,
                trailingCap: $config.splitShapeInfo.trailing.trailingEndCap,
                width: (barWidth - splitSpacing) * 0.6
            )
        }
    }

    private func splitBar(leadingCap: Binding<MenuBarEndCap>, trailingCap: Binding<MenuBarEndCap>, width: CGFloat) -> some View {
        shapeBar(leading: leadingCap.wrappedValue, trailing: trailingCap.wrappedValue)
            .frame(width: width, height: barHeight)
            .overlay(alignment: .leading) { endCapMenu(leadingCap) }
            .overlay(alignment: .trailing) { endCapMenu(trailingCap) }
    }

    private func shapeBar(leading: MenuBarEndCap, trailing: MenuBarEndCap) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: leading == .round ? barHeight / 2 : 4,
            bottomLeadingRadius: leading == .round ? barHeight / 2 : 4,
            bottomTrailingRadius: trailing == .round ? barHeight / 2 : 4,
            topTrailingRadius: trailing == .round ? barHeight / 2 : 4
        )
        .fill(.secondary)
    }

    private func endCapMenu(_ endCap: Binding<MenuBarEndCap>) -> some View {
        Menu {
            Button("Square") { endCap.wrappedValue = .square }
            Button("Round") { endCap.wrappedValue = .round }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 4)
    }
}
