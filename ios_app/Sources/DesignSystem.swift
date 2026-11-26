import SwiftUI

// MARK: - Палитра и стиль в духе нативного iOS Dark Mode

enum AppTheme {
    static let bgPrimary = Color(uiColor: .systemBackground)
    static let bgCard = Color(uiColor: .secondarySystemGroupedBackground)
    static let bgElevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color.white.opacity(0.08)

    static let orange = Color(red: 1.0, green: 0.42, blue: 0.12)
    static let orangeLight = Color(red: 1.0, green: 0.56, blue: 0.22)
    static let mint = Color(uiColor: .systemGreen)
    static let blue = Color(uiColor: .systemBlue)
    static let red = Color(uiColor: .systemRed)

    static let orangeGradient = LinearGradient(
        colors: [orange, orangeLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct DarkCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
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
    func darkCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(DarkCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Модели данных

enum BallSizeOption: Int, CaseIterable, Identifiable, Codable {
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

struct WorkoutRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let durationSec: Int
    let realBounces: Int
    let falseBounces: Int
    let shots: Int
    let tempo: Double
    let avgHeightCm: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSec: Int,
        realBounces: Int,
        falseBounces: Int,
        shots: Int,
        tempo: Double,
        avgHeightCm: Double
    ) {
        self.id = id
        self.date = date
        self.durationSec = durationSec
        self.realBounces = realBounces
        self.falseBounces = falseBounces
        self.shots = shots
        self.tempo = tempo
        self.avgHeightCm = avgHeightCm
    }

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

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.doesRelativeDateFormatting = true
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
}

// MARK: - Хранилище состояния и истории

final class AppStore: ObservableObject {
    @Published var showSkeleton: Bool = true
    @Published var showBallBox: Bool = true
    @Published var showDebugHUD: Bool = true
    @Published var ballSize: BallSizeOption = .size7
    @Published var history: [WorkoutRecord] = []

    private let historyStorageKey = "basketball_workout_history_v1"

    init() {
        loadHistory()
    }

    var totalBounces: Int {
        history.reduce(0) { $0 + $1.realBounces }
    }

    var averageControl: Int {
        guard !history.isEmpty else { return 0 }
        return history.reduce(0) { $0 + $1.controlPercent } / history.count
    }

    func save(_ record: WorkoutRecord) {
        history.insert(record, at: 0)
        persistHistory()
    }

    func delete(_ record: WorkoutRecord) {
        history.removeAll { $0.id == record.id }
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyStorageKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyStorageKey),
              let decoded = try? JSONDecoder().decode([WorkoutRecord].self, from: data) else {
            history = []
            return
        }
        history = decoded
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
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))

            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}