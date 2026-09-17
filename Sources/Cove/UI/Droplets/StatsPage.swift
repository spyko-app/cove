import SwiftUI

struct StatsPage: View {
    @ObservedObject var stats: SystemStats
    let notchTop: CGFloat

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: notchTop)
            Group {
                if #available(macOS 26, *) {
                    GlassEffectContainer(spacing: 4) { grid }
                } else {
                    grid
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .onAppear { stats.retain() }
        .onDisappear { stats.release() }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            CPUCard(percent: stats.cpuPercent)
            MemoryCard(used: stats.memoryUsed, total: stats.memoryTotal)
            DiskCard(free: stats.diskFree, total: stats.diskTotal)
            NetworkCard(up: stats.networkUpRate, down: stats.networkDownRate)
        }
    }
}

private struct StatCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(5)
            .coveCardBackground(cornerRadius: 12)
    }
}

private struct CPUCard: View {
    let percent: Double

    var body: some View {
        StatCard {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(percent.clamped(0, 100)) / 100)
                        .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(StatsFormat.percent(percent))
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    Text(StatsFormat.percent(percent))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct MemoryCard: View {
    let used: UInt64
    let total: UInt64

    private var fraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    var body: some View {
        StatCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memória").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                Text("\(StatsFormat.bytes(used)) / \(StatsFormat.bytes(total))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                UsageBar(fraction: fraction, color: .blue)
            }
        }
    }
}

private struct DiskCard: View {
    let free: UInt64
    let total: UInt64

    private var used: UInt64 { total > free ? total - free : 0 }
    private var fraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    var body: some View {
        StatCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disco").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                Text("\(StatsFormat.bytes(free)) livres")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                UsageBar(fraction: fraction, color: .orange)
            }
        }
    }
}

private struct NetworkCard: View {
    let up: Double
    let down: Double

    var body: some View {
        StatCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rede").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
                    Text(StatsFormat.rate(up))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
                    Text(StatsFormat.rate(down))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.15))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(fraction.clamped(0, 1)))
                }
        }
        .frame(height: 4)
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
