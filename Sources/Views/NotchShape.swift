import SwiftUI

// MARK: - NotchShape

/// 灵动岛外形：顶部完全平直（无视觉缝隙地接续硬件刘海），底部大圆角
struct NotchShape: Shape {
    var bottomCornerRadius: CGFloat = 22
    var topCornerRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottomR = max(0, min(bottomCornerRadius, min(rect.width, rect.height) / 2))
        let topR = max(0, min(topCornerRadius, min(rect.width, rect.height) / 2))

        // 起点：左上角（带可选极小圆角，默认 0）
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topR))
        if topR > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                radius: topR,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        // 顶边
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
        if topR > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topR, y: rect.minY + topR),
                radius: topR,
                startAngle: .degrees(270),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        // 右侧
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomR))
        // 右下圆角
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomR, y: rect.maxY - bottomR),
            radius: bottomR,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // 底边
        path.addLine(to: CGPoint(x: rect.minX + bottomR, y: rect.maxY))
        // 左下圆角
        path.addArc(
            center: CGPoint(x: rect.minX + bottomR, y: rect.maxY - bottomR),
            radius: bottomR,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
