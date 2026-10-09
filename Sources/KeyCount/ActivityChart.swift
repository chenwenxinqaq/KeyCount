import SwiftUI

struct ActivityPoint: Identifiable {
    let id: Int
    let label: String
    let detail: String
    let value: Int
    var highlighted = false
}

struct ActivityChart: View {
    let points: [ActivityPoint]
    let unit: String
    let emptyText: String
    @State private var selectedID: Int?
    @State private var hoveredID: Int?

    private var selected: ActivityPoint? {
        points.first { $0.id == (hoveredID ?? selectedID) }
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                if let selected {
                    Text("\(selected.detail) · \(selected.value.formatted()) \(unit)")
                        .foregroundStyle(selected.value < 0 ? Theme.warning : Theme.accent)
                } else if points.allSatisfy({ $0.value == 0 }) {
                    Text(emptyText).foregroundStyle(.secondary)
                } else {
                    Text("悬停或点按查看数值").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10))
            .lineLimit(1)

            GeometryReader { geometry in
                let plotHeight = geometry.size.height - 23
                let scale = ActivityScale(values: points.map(\.value))
                let zeroY = CGFloat(scale.zeroPosition) * plotHeight
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .offset(y: zeroY)

                    HStack(alignment: .top, spacing: points.count > 7 ? 4 : 12) {
                        ForEach(points) { point in
                            Button {
                                selectedID = selectedID == point.id ? nil : point.id
                            } label: {
                                VStack(spacing: 9) {
                                    GeometryReader { bar in
                                        let valueY = CGFloat(scale.position(for: point.value)) * plotHeight
                                        let height = max(abs(zeroY - valueY), 2)
                                        RoundedRectangle(cornerRadius: points.count > 7 ? 2 : 4)
                                            .fill(barColor(point))
                                            .frame(width: bar.size.width, height: height)
                                            .offset(y: min(min(zeroY, valueY), plotHeight - height))
                                    }
                                    .frame(height: plotHeight)
                                    Text(point.label.isEmpty ? " " : point.label)
                                        .font(.system(size: 10, weight: point.highlighted ? .semibold : .regular))
                                        .foregroundStyle(point.highlighted ? Theme.accent : Color.secondary)
                                        .frame(height: 14)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering { hoveredID = point.id }
                                else if hoveredID == point.id { hoveredID = nil }
                            }
                            .help("\(point.detail)：\(point.value.formatted()) \(unit)")
                            .accessibilityLabel(point.detail)
                            .accessibilityValue("\(point.value.formatted()) \(unit)")
                        }
                    }
                }
            }
            .frame(height: 94)
        }
    }

    private func barColor(_ point: ActivityPoint) -> Color {
        if point.value == 0 { return Color.primary.opacity(0.09) }
        if point.value < 0 { return Theme.warning.opacity(0.85) }
        if selected?.id == point.id || point.highlighted { return Theme.accent }
        return Theme.accent.opacity(0.33)
    }
}
