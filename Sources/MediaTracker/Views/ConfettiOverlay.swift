import SwiftUI

struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Date = .now
    let duration: TimeInterval = 2.2

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                guard elapsed < duration else { return }

                for particle in particles {
                    let progress = elapsed / duration
                    let t = elapsed * particle.speed

                    let x = particle.origin.x + particle.velocityX * t
                    let y = particle.origin.y + particle.velocityY * t + 0.5 * particle.gravity * t * t
                    let rotation = particle.rotation + particle.rotationSpeed * t
                    let opacity = max(0, 1.0 - progress * 1.2)
                    let scale = particle.scale * (1.0 - progress * 0.3)

                    var ctx = context
                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .degrees(rotation))
                    ctx.scaleBy(x: scale, y: scale)

                    let rect = CGRect(
                        x: -particle.size / 2,
                        y: -particle.size / 2,
                        width: particle.size,
                        height: particle.size * particle.aspectRatio
                    )

                    if particle.isCircle {
                        ctx.fill(Path(ellipseIn: rect), with: .color(particle.color))
                    } else {
                        ctx.fill(Path(rect), with: .color(particle.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task {
            generateParticles()
        }
    }

    private func generateParticles() {
        let screenWidth = NSScreen.main?.frame.width ?? 800
        let screenHeight = NSScreen.main?.frame.height ?? 600
        let centerX = screenWidth / 2
        let centerY = screenHeight * 0.35

        let confettiColors: [Color] = [
            .pink, .purple, .blue, .green, .orange, .yellow,
            .red, .cyan, .mint, .indigo,
        ]

        let count = 80
        particles = (0..<count).map { i in
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 120...350)
            return ConfettiParticle(
                origin: CGPoint(
                    x: centerX + CGFloat.random(in: -60...60),
                    y: centerY + CGFloat.random(in: -20...20)
                ),
                velocityX: cos(angle) * speed * 0.4,
                velocityY: -abs(sin(angle)) * speed,
                gravity: Double.random(in: 280...450),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -400...400),
                size: CGFloat.random(in: 5...12),
                aspectRatio: CGFloat.random(in: 0.4...1.5),
                color: confettiColors[i % confettiColors.count],
                scale: CGFloat.random(in: 0.8...1.2),
                speed: Double.random(in: 0.9...1.1),
                isCircle: Bool.random()
            )
        }
    }
}

private struct ConfettiParticle {
    let origin: CGPoint
    let velocityX: Double
    let velocityY: Double
    let gravity: Double
    let rotation: Double
    let rotationSpeed: Double
    let size: CGFloat
    let aspectRatio: CGFloat
    let color: Color
    let scale: CGFloat
    let speed: Double
    let isCircle: Bool
}
