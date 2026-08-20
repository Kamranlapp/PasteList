import SwiftUI

struct FeatureTipBubble: View {
    let lines: [String]
    let arrowOffsetX: CGFloat
    let stepIndex: Int
    let stepCount: Int
    let onNext: () -> Void

    var body: some View {
        CoachMarkCard(
            arrowOffsetX: arrowOffsetX,
            arrowEdge: .bottom,
            stepIndex: stepIndex,
            stepCount: stepCount,
            onNext: onNext
        ) {
            CoachMarkText(lines: lines)
        }
    }
}
