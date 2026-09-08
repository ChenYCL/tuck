import AppKit
import SwiftUI

/// An interactive horizontal bar for editing a `CustomGradient`'s color stops: tap an
/// empty area to add a stop, drag a handle to reposition it, tap a handle to edit its
/// color, and double-tap a handle to remove it.
struct GradientEditor: View {
    @Binding var gradient: CustomGradient

    @State private var selectedStopID: UUID?

    private let barWidth: CGFloat = 300
    private let barHeight: CGFloat = 24
    private let handleSize: CGFloat = 14
    private let coordinateSpaceName = "GradientEditor.bar"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                bar
                ForEach(gradient.stops) { stop in
                    handle(for: stop)
                }
            }
            .frame(width: barWidth, height: barHeight)
            .coordinateSpace(.named(coordinateSpaceName))

            if let selectedStopID, let index = gradient.stops.firstIndex(where: { $0.id == selectedStopID }) {
                ColorPicker(
                    "Stop color",
                    selection: Binding(
                        get: { Color(nsColor: gradient.stops[index].color.nsColor) },
                        set: { gradient.stops[index].color = CodableColor(NSColor($0)) }
                    ),
                    supportsOpacity: true
                )
            }
        }
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: barHeight / 2)
            .fill(barGradient)
            .frame(width: barWidth, height: barHeight)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                    .onEnded { value in addStop(at: value.location.x) }
            )
    }

    private var barGradient: LinearGradient {
        let stops = gradient.sortedStops.map {
            Gradient.Stop(color: Color(nsColor: $0.color.nsColor), location: $0.location.clamped(to: 0...1))
        }
        guard !stops.isEmpty else {
            return LinearGradient(colors: [.black], startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private func handle(for stop: ColorStop) -> some View {
        let isSelected = selectedStopID == stop.id
        return Circle()
            .fill(Color(nsColor: stop.color.nsColor))
            .frame(width: handleSize, height: handleSize)
            .overlay(
                Circle().strokeBorder(isSelected ? Color.accentColor : Color.white, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(radius: 1)
            .position(x: stop.location.clamped(to: 0...1) * barWidth, y: barHeight / 2)
            .simultaneousGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in move(stop, to: value.location.x) }
            )
            .gesture(
                TapGesture(count: 2)
                    .onEnded { remove(stop) }
                    .exclusively(before: TapGesture(count: 1).onEnded { selectedStopID = stop.id })
            )
    }

    private func addStop(at x: CGFloat) {
        let location = (x / barWidth).clamped(to: 0...1)
        let color = gradient.color(at: location)?.cgColor ?? NSColor.black.cgColor
        let stop = ColorStop(color: color, location: location)
        gradient.stops.append(stop)
        selectedStopID = stop.id
    }

    private func move(_ stop: ColorStop, to x: CGFloat) {
        guard let index = gradient.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        gradient.stops[index].location = (x / barWidth).clamped(to: 0...1)
    }

    private func remove(_ stop: ColorStop) {
        guard gradient.stops.count > 1 else { return }
        gradient.stops.removeAll { $0.id == stop.id }
        if selectedStopID == stop.id { selectedStopID = nil }
    }
}
