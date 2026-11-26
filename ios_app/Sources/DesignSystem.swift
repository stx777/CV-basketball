import SwiftUI

// MARK: - Палитра и стиль приложения

enum AppTheme {
    static let bgPrimary = Color(red: 0.043, green: 0.051, blue: 0.071)   // #0B0D12
    static let bgCard = Color(red: 0.082, green: 0.098, blue: 0.133)      // #151922
    static let bgElevated = Color(red: 0.118, green: 0.141, blue: 0.192)  // #1E2431
    static let border = Color.white.opacity(0.08)

    static let orange = Color(red: 1.0, green: 0.42, blue: 0.10)          // #FF6B1A
    static let orangeLight = Color(red: 1.0, green: 0.57, blue: 0.17)     // #FF912B
    static let mint = Color(red: 0.18, green: 0.90, blue: 0.62)           // #2EE59D
    static let blue = Color(red: 0.22, green: 0.74, blue: 0.97)           // #38BDF8
    static let red = Color(red: 1.0, green: 0.28, blue: 0.34)             // #FF4757

    static let orangeGradient = LinearGradient(
        colors: [orange, orangeLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct DarkCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func darkCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(DarkCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Модели тренировок и настроек

enum WorkoutMode: String, CaseIterable, Identifiable {
    case freeDribble = "Свободный дриблинг"
    case speedTempo = "Скоростной темп"
    case controlDrill = "Контроль и высота"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .freeDribble: return "Базовый учёт ударов, высоты и темпа"
        case .speedTempo: return "Фокус на частоту ударов в секунду"
        case .controlDrill: return "Минимум потерь и стабильная высота"
        }
    }

    var icon: String {
        switch self {
        case .freeDribble: return "basketball.fill"
        case .speedTempo: return "bolt.fill"
        case .controlDrill: return "scope"
        }
    }

    var accentColor: Color {
        switch self {
        case .freeDribble: return AppTheme.orange
        case .speedTempo: return AppTheme.mint
        case .controlDrill: return AppTheme.blue
        }
    }
}

enum BallSizeOption: Int, CaseIterable, Identifiable {
    case size5 = 5
    case size6 = 6
    case size7 = 7

    var id: Int { rawValue }

    var title: String { "№\(rawValue)" }

    var diameterCm: CGFloat {
        switch self {
        case .size5: return 22.0
        case .size6: return 23.0
        case .size7: return 24.0
        }
    }
}

struct WorkoutRecord: Identifiable {
    let id = UUID()
    let date: Date
    let mode: WorkoutMode
    let durationSec: Int
    let realBounces: Int
    let falseBounces: Int
    let shots: Int
    let tempo: Double
    let avgHeightCm: Double

    var controlPercent: Int {
        let total = realBounces + falseBounces
        guard total > 0 else { return 100 }
        return Int((Double(realBounces) / Double(total) * 100.0).rounded())
    }

    var formattedDuration: String {
        let m = durationSec / 60
        let s = durationSec % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Общее состояние приложения

final class AppStore: ObservableObject {
    @Published var selectedMode: WorkoutMode = .freeDribble
    @Published var showSkeleton: Bool = true
    @Published var showBallBox: Bool = true
    @Published var showDebugHUD: Bool = true
    @Published var ballSize: BallSizeOption = .size7

    @Published var history: [WorkoutRecord] = [
        WorkoutRecord(
            date: Date().addingTimeInterval(-3600 * 5),
            mode: .speedTempo,
            durationSec: 215,
            realBounces: 348,
            falseBounces: 9,
            shots: 6,
            tempo: 1.92,
            avgHeightCm: 76.4
        ),
        WorkoutRecord(
            date: Date().addingTimeInterval(-86400),
            mode: .freeDribble,
            durationSec: 340,
            realBounces: 492,
            falseBounces: 18,
            shots: 14,
            tempo: 1.54,
            avgHeightCm: 88.2
        ),
        WorkoutRecord(
            date: Date().addingTimeInterval(-86400 * 2),
            mode: .controlDrill,
            durationSec: 180,
            realBounces: 265,
            falseBounces: 4,
            shots: 2,
            tempo: 1.61,
            avgHeightCm: 71.0
        )
    ]

    var todayBounces: Int {
        let cal = Calendar.current
        return history
            .filter { cal.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.realBounces }
    }

    var averageControl: Int {
        guard !history.isEmpty else { return 0 }
        let sum = history.reduce(0) { $0 + $1.controlPercent }
        return sum / history.count
    }

    var bestTempo: Double {
        history.map(\.tempo).max() ?? 0.0
    }

    func save(_ record: WorkoutRecord) {
        history.insert(record, at: 0)
    }
}

// MARK: - Общие UI-компоненты

struct GlassCircleButton: View {
    let icon: String
    var tint: Color = .white
    var size: CGFloat = 44
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(isActive ? AppTheme.orange : tint)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(isActive ? AppTheme.orange.opacity(0.6) : Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct CompactStatPill: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.6)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}