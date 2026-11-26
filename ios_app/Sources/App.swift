import SwiftUI

@main
struct BasketballApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Главная навигация (3 вкладки)

struct RootTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab = 0
    @State private var isWorkoutPresented = false

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.055, green: 0.065, blue: 0.090, alpha: 0.96)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onStartWorkout: { isWorkoutPresented = true })
                .tabItem {
                    Label("Тренировка", systemImage: "basketball.fill")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("История", systemImage: "chart.bar.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "slider.horizontal.3")
                }
                .tag(2)
        }
        .tint(AppTheme.orange)
        .fullScreenCover(isPresented: $isWorkoutPresented) {
            CameraWorkoutView(
                mode: store.selectedMode,
                showSkeleton: store.showSkeleton,
                showBallBox: store.showBallBox,
                showDebugHUD: store.showDebugHUD
            )
            .environmentObject(store)
        }
    }
}

// MARK: - Экран 1: Главная (Dashboard)

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    let onStartWorkout: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection
                    heroStartCard
                    modeSelectorSection
                    todayStatsSection

                    if let last = store.history.first {
                        lastWorkoutSection(last)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(AppTheme.bgPrimary.ignoresSafeArea())
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOOPVISION AI")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.orange)
                    .tracking(1.4)

                Text("Готов к дриблингу?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppTheme.orange)
                Text("\(store.history.count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.bgCard)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
        }
    }

    private var heroStartCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(store.selectedMode.rawValue, systemImage: store.selectedMode.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.orangeLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.orange.opacity(0.16))
                        .clipShape(Capsule())

                    Text("Анализ в реальном времени")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 4)

                    Text(store.selectedMode.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(AppTheme.orange.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.orangeGradient)
                }
            }

            Button(action: onStartWorkout) {
                HStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Начать тренировку")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.orangeGradient)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: AppTheme.orange.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            ZStack {
                AppTheme.bgCard
                LinearGradient(
                    colors: [AppTheme.orange.opacity(0.18), .clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.orange.opacity(0.28), lineWidth: 1)
        )
    }

    private var modeSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Режим тренировки")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WorkoutMode.allCases) { mode in
                        let isSelected = store.selectedMode == mode
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                store.selectedMode = mode
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : mode.accentColor)
                                    .frame(width: 36, height: 36)
                                    .background(isSelected ? mode.accentColor : mode.accentColor.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                Text(mode.rawValue)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(mode.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(width: 158, alignment: .leading)
                            .padding(14)
                            .background(isSelected ? AppTheme.bgElevated : AppTheme.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(isSelected ? mode.accentColor : AppTheme.border, lineWidth: isSelected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var todayStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Твоя форма")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                metricTile(title: "Удары сегодня", value: "\(store.todayBounces)", unit: "уд", color: AppTheme.orange)
                metricTile(title: "Лучший темп", value: String(format: "%.2f", store.bestTempo), unit: "уд/с", color: AppTheme.mint)
                metricTile(title: "Контроль", value: "\(store.averageControl)%", unit: "ср.", color: AppTheme.blue)
            }
        }
    }

    private func metricTile(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkCard(cornerRadius: 16, padding: 14)
    }

    private func lastWorkoutSection(_ record: WorkoutRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последняя сессия")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            WorkoutRowCard(record: record)
        }
    }
}

// MARK: - Экран 2: Live Camera HUD

struct CameraWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    let mode: WorkoutMode
    let showDebugHUD: Bool

    @StateObject private var session: CameraSessionStore
    @State private var finishedRecord: WorkoutRecord?

    init(mode: WorkoutMode, showSkeleton: Bool, showBallBox: Bool, showDebugHUD: Bool) {
        self.mode = mode
        self.showDebugHUD = showDebugHUD
        _session = StateObject(wrappedValue: CameraSessionStore(showSkeleton: showSkeleton, showBallBox: showBallBox))
    }

    var body: some View {
        ZStack {
            // Слой живой камеры + Vision/Core ML оверлеи
            CameraPreviewRepresentable(session: session)
                .ignoresSafeArea()

            // Мягкие виньетки для идеальной читаемости HUD
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.65), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)

                Spacer()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Интерфейс поверх камеры
            VStack {
                topHUD
                Spacer()
                if session.isPaused {
                    pausedBanner
                    Spacer()
                }
                bottomHUD
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .statusBarHidden(true)
        .sheet(item: $finishedRecord, onDismiss: {
            dismiss()
        }) { record in
            WorkoutSummaryView(record: record) {
                store.save(record)
                finishedRecord = nil
            } onDiscard: {
                finishedRecord = nil
            }
            .preferredColorScheme(.dark)
        }
    }

    private var topHUD: some View {
        HStack(spacing: 10) {
            // Пилюля статуса и таймера
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isPaused ? Color.yellow : AppTheme.red)
                        .frame(width: 8, height: 8)
                    Text(session.formattedElapsed)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                if showDebugHUD {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1, height: 14)

                    Text(String(format: "%.0f FPS", session.fps))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(session.fps >= 24 ? AppTheme.mint : .yellow)

                    Text(session.modelStatus)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(session.isModelReady ? AppTheme.mint : AppTheme.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((session.isModelReady ? AppTheme.mint : AppTheme.red).opacity(0.16))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))

            Spacer()

            GlassCircleButton(
                icon: "figure.walk",
                isActive: session.showSkeleton
            ) {
                session.toggleSkeleton()
            }

            GlassCircleButton(icon: "camera.rotate.fill") {
                session.switchCamera()
            }

            GlassCircleButton(icon: "xmark") {
                session.stop()
                dismiss()
            }
        }
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.yellow)
            Text("ПАУЗА")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.yellow.opacity(0.45), lineWidth: 1))
    }

    private var bottomHUD: some View {
        VStack(spacing: 14) {
            // Стеклянная панель метрик
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    // Главный счётчик ударов
                    VStack(alignment: .leading, spacing: 2) {
                        Text("УДАРЫ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.orangeLight)
                            .tracking(1.0)

                        Text("\(session.metrics.realBounces)")
                            .font(.system(size: 46, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.white)
                            .animation(.snappy, value: session.metrics.realBounces)
                    }
                    .frame(minWidth: 96, alignment: .leading)

                    // Правая сетка 2x1: Темп и Высота
                    HStack(spacing: 8) {
                        CompactStatPill(
                            title: "Темп",
                            value: String(format: "%.2f уд/с", session.metrics.tempo),
                            accent: AppTheme.mint
                        )
                        CompactStatPill(
                            title: "Высота",
                            value: String(format: "%.0f см", session.metrics.avgBounceHeightCm),
                            accent: AppTheme.blue
                        )
                    }
                }

                // Нижняя строка вторичных показателей
                HStack(spacing: 0) {
                    miniFooterStat(label: "Броски", value: "\(session.metrics.shots)", color: .white)
                    Divider().frame(height: 16).background(Color.white.opacity(0.15))
                    miniFooterStat(label: "Потери", value: "\(session.metrics.falseBounces)", color: AppTheme.red)
                    Divider().frame(height: 16).background(Color.white.opacity(0.15))
                    miniFooterStat(label: "Контроль", value: "\(session.controlPercent)%", color: AppTheme.mint)
                }
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )

            // Панель управления сессией
            HStack(spacing: 16) {
                GlassCircleButton(icon: "arrow.counterclockwise", size: 54) {
                    session.reset()
                }

                Button {
                    session.togglePause()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text(session.isPaused ? "Продолжить" : "Пауза")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(session.isPaused ? AppTheme.orangeGradient : LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    session.stop()
                    finishedRecord = session.buildRecord(mode: mode)
                } label: {
                    Text("Финиш")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .background(AppTheme.red)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func miniFooterStat(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Экран 3: Итоги тренировки

struct WorkoutSummaryView: View {
    let record: WorkoutRecord
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.orange.opacity(0.18))
                        .frame(width: 72, height: 72)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.orangeGradient)
                }

                Text("Тренировка завершена")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(record.mode.rawValue) · \(record.formattedDuration)")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summaryBox(title: "Удары", value: "\(record.realBounces)", color: AppTheme.orange)
                summaryBox(title: "Темп", value: String(format: "%.2f уд/с", record.tempo), color: AppTheme.mint)
                summaryBox(title: "Ср. высота", value: String(format: "%.1f см", record.avgHeightCm), color: AppTheme.blue)
                summaryBox(title: "Броски / Потери", value: "\(record.shots) / \(record.falseBounces)", color: .white)
            }

            // Полоса контроля мяча
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Контроль мяча")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(record.controlPercent)%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.mint)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(AppTheme.mint)
                            .frame(width: geo.size.width * CGFloat(record.controlPercent) / 100.0)
                    }
                }
                .frame(height: 10)
            }
            .darkCard(cornerRadius: 18, padding: 16)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onSave) {
                    Text("Сохранить в историю")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.orangeGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDiscard) {
                    Text("Удалить сессию")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(AppTheme.bgPrimary.ignoresSafeArea())
    }

    private func summaryBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkCard(cornerRadius: 16, padding: 14)
    }
}

// MARK: - Экран 4: История

struct HistoryView: View {
    @EnvironmentObject var store: AppStore

    private let weekDemo: [(String, CGFloat)] = [
        ("Пн", 0.45), ("Вт", 0.72), ("Ср", 0.30),
        ("Чт", 0.90), ("Пт", 0.62), ("Сб", 1.0), ("Вс", 0.55)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("История")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    weeklyChartCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Все тренировки")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        ForEach(store.history) { record in
                            WorkoutRowCard(record: record)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(AppTheme.bgPrimary.ignoresSafeArea())
        }
    }

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Активность за неделю")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Всего ударов: \(store.history.reduce(0) { $0 + $1.realBounces })")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(AppTheme.orange)
            }

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(weekDemo, id: \.0) { day, ratio in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ratio > 0.85 ? AppTheme.orangeGradient : LinearGradient(colors: [AppTheme.bgElevated, AppTheme.bgElevated], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(14, 96 * ratio))
                        Text(day)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
        .darkCard(cornerRadius: 20, padding: 16)
    }
}

struct WorkoutRowCard: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(record.mode.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: record.mode.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(record.mode.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.mode.rawValue)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(record.formattedDuration) · Контроль \(record.controlPercent)%")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(record.realBounces)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(String(format: "%.2f уд/с", record.tempo))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mint)
            }
        }
        .darkCard(cornerRadius: 18, padding: 14)
    }
}

// MARK: - Экран 5: Настройки

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Настройки")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("ОТОБРАЖЕНИЕ НА КАМЕРЕ")

                        Toggle("Скелет игрока (Vision)", isOn: $store.showSkeleton)
                            .tint(AppTheme.orange)
                        Divider().background(AppTheme.border)
                        Toggle("Рамка мяча (YOLO)", isOn: $store.showBallBox)
                            .tint(AppTheme.orange)
                        Divider().background(AppTheme.border)
                        Toggle("Показывать FPS и статус AI", isOn: $store.showDebugHUD)
                            .tint(AppTheme.orange)
                    }
                    .foregroundStyle(.white)
                    .darkCard(cornerRadius: 20, padding: 16)

                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("КАЛИБРОВКА МЯЧА")

                        Text("Размер мяча для расчёта высоты отскока")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.75))

                        Picker("Размер мяча", selection: $store.ballSize) {
                            ForEach(BallSizeOption.allCases) { size in
                                Text("\(size.title) (\(Int(size.diameterCm)) см)").tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .darkCard(cornerRadius: 20, padding: 16)

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("СКОРО В ОБНОВЛЕНИЯХ")

                        futureFeatureRow(icon: "waveform", title: "Голосовые подсказки темпа", badge: "План")
                        Divider().background(AppTheme.border)
                        futureFeatureRow(icon: "film.stack", title: "Экспорт видео со скелетом", badge: "План")
                    }
                    .darkCard(cornerRadius: 20, padding: 16)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(AppTheme.bgPrimary.ignoresSafeArea())
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AppTheme.orangeLight)
            .tracking(1.0)
    }

    private func futureFeatureRow(icon: String, title: String, badge: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(badge)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}