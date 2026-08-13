import AppKit
import SwiftUI

enum QuickPasteShortcut {
    static let maximumEntryCount = 10

    static func label(forEntryIndex index: Int) -> String? {
        guard (0..<maximumEntryCount).contains(index) else {
            return nil
        }
        return index == maximumEntryCount - 1 ? "0" : String(index + 1)
    }

    static func entryIndex(
        forKeyCode keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> Int? {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return nil
        }

        switch keyCode {
        case 18, 83: return 0 // 1 and numeric keypad 1
        case 19, 84: return 1 // 2 and numeric keypad 2
        case 20, 85: return 2 // 3 and numeric keypad 3
        case 21, 86: return 3 // 4 and numeric keypad 4
        case 23, 87: return 4 // 5 and numeric keypad 5
        case 22, 88: return 5 // 6 and numeric keypad 6
        case 26, 89: return 6 // 7 and numeric keypad 7
        case 28, 91: return 7 // 8 and numeric keypad 8
        case 25, 92: return 8 // 9 and numeric keypad 9
        case 29, 82: return 9 // 0 and numeric keypad 0
        default: return nil
        }
    }
}

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
