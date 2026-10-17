import AppKit
import SwiftUI

enum SecretSweepTrigger {
    static func isActive(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        let relevant = modifiers.intersection(.deviceIndependentFlagsMask)
        return relevant.contains([.command, .option])
    }
}

struct SecretSweepView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var swept = false
    @State private var revealed = false

    private let shards = [
        ShardSpec(x: -155, y: -42, rotation: -18, scale: 1.05),
        ShardSpec(x: -112, y: 8, rotation: 16, scale: 0.82),
        ShardSpec(x: -66, y: -55, rotation: 42, scale: 0.66),
        ShardSpec(x: -22, y: 15, rotation: -36, scale: 0.92),
        ShardSpec(x: 20, y: -30, rotation: 74, scale: 0.58),
        ShardSpec(x: 54, y: 22, rotation: 12, scale: 0.72)
    ]

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.18), Color.purple.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                ForEach(shards) { shard in
                    AngularShard()
                        .fill(
                            LinearGradient(
                                colors: [.red, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 54)
                        .scaleEffect(shard.scale)
                        .rotationEffect(.degrees(shard.rotation))
                        .offset(
                            x: shard.x + (swept ? 245 : 0),
                            y: shard.y + (swept ? 72 : 0)
                        )
                        .scaleEffect(swept ? 0.18 : 1)
                        .opacity(swept ? 0 : 1)
                }

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 62, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .offset(x: 154, y: 62)
                    .overlay(alignment: .top) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .offset(x: 154, y: swept ? 20 : 70)
                            .opacity(swept ? 1 : 0)
                    }

                BroomGraphic()
                    .frame(width: 150, height: 82)
                    .rotationEffect(.degrees(swept ? -7 : -18))
                    .offset(x: swept ? 112 : -178, y: swept ? 28 : -8)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
            }
            .frame(width: 470, height: 230)
            .clipped()

            VStack(spacing: 7) {
                Text(primaryMessage)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(secondaryMessage)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                Text("Secret Sweep • Veress Róbert, 2026")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 8)

            Button(L10n.text("Vissza az AbeSweephez", "Back to AbeSweep")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(30)
        .frame(width: 540, height: 440)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 1.05)) {
                swept = true
            }
            try? await Task.sleep(for: .milliseconds(780))
            withAnimation(.easeOut(duration: 0.45)) {
                revealed = true
            }
        }
    }

    private var primaryMessage: String {
        L10n.text("A seprű alatt minden kiderül.", "Nothing escapes the sweep.")
    }

    private var secondaryMessage: String {
        L10n.text("Nothing escapes the sweep.", "A seprű alatt minden kiderül.")
    }
}

private struct ShardSpec: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let scale: CGFloat
}

private struct AngularShard: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX * 0.82, y: rect.maxY * 0.72))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct BroomGraphic: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.23, blue: 0.10), .brown],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 112, height: 9)
                .rotationEffect(.degrees(-18))
                .offset(x: -16, y: -12)

            BroomBristles()
                .fill(
                    LinearGradient(
                        colors: [.orange, Color(red: 0.78, green: 0.42, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 58, height: 66)
                .rotationEffect(.degrees(-18))
                .offset(x: 50, y: 17)

            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(.yellow.opacity(0.65))
                    .frame(width: 3, height: 42)
                    .rotationEffect(.degrees(Double(index - 1) * 5 - 18))
                    .offset(x: CGFloat(39 + index * 8), y: 24)
            }
        }
    }
}

private struct BroomBristles: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08)
        )
        path.addLine(to: CGPoint(x: rect.maxX * 0.94, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY * 0.88),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.04)
        )
        path.closeSubpath()
        return path
    }
}
