import SwiftUI

struct FeatureTipArrowBubble: View {
    let lines: [String]
    let arrowOffsetX: CGFloat
    let stepIndex: Int
    let stepCount: Int
    let onNext: () -> Void

    var body: some View {
        CoachMarkCard(
            arrowOffsetX: arrowOffsetX,
            arrowEdge: .top,
            stepIndex: stepIndex,
            stepCount: stepCount,
            onNext: onNext
        ) {
            CoachMarkText(lines: lines)
        }
    }
}

struct CoachMarkText: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                    .foregroundStyle(CoachMarkStyle.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CoachMarkCard<Content: View>: View {
    let arrowOffsetX: CGFloat
    let arrowEdge: CoachMarkPointerEdge
    let stepIndex: Int
    let stepCount: Int
    let onNext: () -> Void
    let content: Content

    init(
        arrowOffsetX: CGFloat,
        arrowEdge: CoachMarkPointerEdge,
        stepIndex: Int,
        stepCount: Int,
        onNext: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.arrowOffsetX = arrowOffsetX
        self.arrowEdge = arrowEdge
        self.stepIndex = stepIndex
        self.stepCount = stepCount
        self.onNext = onNext
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, arrowEdge == .top ? 4 : 0)

            CoachMarkFooter(
                stepIndex: stepIndex,
                stepCount: stepCount,
                onNext: onNext
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
        }
        .padding(12)
        .frame(
            width: CoachMarkStyle.cardSize.width,
            height: CoachMarkStyle.cardSize.height,
            alignment: .topLeading
        )
        .background {
            CoachMarkBubbleShape(
                arrowOffsetX: arrowOffsetX,
                arrowEdge: arrowEdge
            )
            .fill(CoachMarkStyle.background)
        }
        .overlay {
            CoachMarkBubbleShape(
                arrowOffsetX: arrowOffsetX,
                arrowEdge: arrowEdge
            )
            .stroke(CoachMarkStyle.border, lineWidth: 1)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

struct CoachMarkFooter: View {
    let stepIndex: Int
    let stepCount: Int
    let onNext: () -> Void

    private var isLastStep: Bool { stepIndex == stepCount - 1 }

    var body: some View {
        HStack {
            Text("\(stepIndex + 1)/\(stepCount)")
                .font(.system(size: 10))
                .foregroundStyle(CoachMarkStyle.secondaryText)

            Spacer()

            Button(isLastStep ? "Got it" : "Next", action: onNext)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(height: 16)
    }
}

enum CoachMarkPointerEdge {
    case top
    case bottom
}

struct CoachMarkBubbleShape: Shape {
    let arrowOffsetX: CGFloat
    let arrowEdge: CoachMarkPointerEdge
    private let cornerRadius: CGFloat = 14
    private let arrowWidth: CGFloat = 24
    private let arrowHeight: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let bodyMinY = arrowEdge == .top ? arrowHeight : 0
        let bodyMaxY = arrowEdge == .bottom
            ? rect.maxY - arrowHeight
            : rect.maxY
        let clampedX = min(
            max(arrowOffsetX, rect.minX + cornerRadius),
            rect.maxX - cornerRadius
        )
        let arrowLeft = max(
            clampedX - arrowWidth / 2,
            rect.minX + cornerRadius
        )
        let arrowRight = min(
            clampedX + arrowWidth / 2,
            rect.maxX - cornerRadius
        )
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: bodyMinY))
        if arrowEdge == .top {
            path.addLine(to: CGPoint(x: arrowLeft, y: bodyMinY))
            path.addLine(to: CGPoint(x: clampedX, y: rect.minY))
            path.addLine(to: CGPoint(x: arrowRight, y: bodyMinY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: bodyMinY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyMinY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: bodyMinY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyMaxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: bodyMaxY),
            control: CGPoint(x: rect.maxX, y: bodyMaxY)
        )
        if arrowEdge == .bottom {
            path.addLine(to: CGPoint(x: arrowRight, y: bodyMaxY))
            path.addLine(to: CGPoint(x: clampedX, y: rect.maxY))
            path.addLine(to: CGPoint(x: arrowLeft, y: bodyMaxY))
        }
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: bodyMaxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: bodyMaxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: bodyMaxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyMinY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: bodyMinY),
            control: CGPoint(x: rect.minX, y: bodyMinY)
        )
        path.closeSubpath()

        return path
    }
}

enum CoachMarkStyle {
    static let cardSize = CGSize(width: 250, height: 120)
    static let background = Color(red: 0.965, green: 0.965, blue: 0.975)
    static let primaryText = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let secondaryText = Color(red: 0.38, green: 0.38, blue: 0.42)
    static let border = Color.black.opacity(0.14)
}
