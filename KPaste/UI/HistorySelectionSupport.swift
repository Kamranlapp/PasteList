import SwiftUI

struct ClipRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]

    static func reduce(
        value: inout [Int64: CGRect],
        nextValue: () -> [Int64: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

struct SelectionBackgroundShape: Shape {
    let roundsTopCorners: Bool
    let roundsBottomCorners: Bool
    private let cornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let maximumRadius = min(rect.width, rect.height) / 2
        let topRadius = roundsTopCorners ? min(cornerRadius, maximumRadius) : 0
        let bottomRadius = roundsBottomCorners ? min(cornerRadius, maximumRadius) : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
