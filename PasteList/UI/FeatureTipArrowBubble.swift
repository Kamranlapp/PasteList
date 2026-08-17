import SwiftUI

struct FeatureTipArrowBubble: View {
    let text: String
    let arrowOffsetX: CGFloat
    let stepIndex: Int
    let stepCount: Int
    let onNext: () -> Void

    private var isLastStep: Bool { stepIndex == stepCount - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if stepCount > 1 {
                    Text("\(stepIndex + 1)/\(stepCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isLastStep ? "Got it" : "Next", action: onNext)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .padding(.top, Self.arrowHeight)
        .frame(width: 210, alignment: .leading)
        .background(
            CoachMarkBubbleShape(arrowOffsetX: arrowOffsetX)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    fileprivate static let arrowHeight: CGFloat = 7
}

private struct CoachMarkBubbleShape: Shape {
    let arrowOffsetX: CGFloat
    private let cornerRadius: CGFloat = 14
    private let arrowWidth: CGFloat = 14
    private var arrowHeight: CGFloat { FeatureTipArrowBubble.arrowHeight }

    func path(in rect: CGRect) -> Path {
        let bodyRect = CGRect(
            x: rect.minX,
            y: rect.minY + arrowHeight,
            width: rect.width,
            height: rect.height - arrowHeight
        )
        var path = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: bodyRect)

        let clampedX = min(max(arrowOffsetX, arrowWidth), rect.width - arrowWidth)
        path.move(to: CGPoint(x: clampedX - arrowWidth / 2, y: arrowHeight))
        path.addLine(to: CGPoint(x: clampedX, y: 0))
        path.addLine(to: CGPoint(x: clampedX + arrowWidth / 2, y: arrowHeight))
        path.closeSubpath()

        return path
    }
}
