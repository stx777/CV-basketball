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

// MARK: - Главная навигация

struct RootTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab = 0
    @State private var isWorkoutPresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onStartWorkout: { isWorkoutPresented = true })
                .tabItem {
                    Label("Тренировка", systemImage: "basketball.fill")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("История", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(AppTheme.orange)
        .fullScreenCover(isPresented: $isWorkoutPresented) {
            CameraWorkoutView(
                showSkeleton: store.showSkeleton,
                showBallBox: store.showBallBox,
                showDebugHUD: store.showDebugHUD
            )
            .environmentObject(store)
        }
    }
}

// MARK: - Экран 1: Главная

struct HomeView: View {
    let onStartWorkout: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Начинаем?")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 8)

                    heroStartCard
                    modeDescriptionCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(AppTheme.bgPrimary.ignoresSafeArea())
        }
    }

    private var heroStartCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Свободный дриблинг", systemImage: "basketball.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.orangeLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.orange.opacity(0.16))
                        .clipShape(Capsule())

                    Text("Анализ в реальном времени")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(AppTheme.orange.opacity(0.16))
                        .frame(width: 54, height: 54)
                    Image(systemName: "basketball.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.orangeGradient)
                }
            }

            Button(action: onStartWorkout) {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.headline)
                    Text("Начать тренировку")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppTheme.orangeGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            ZStack {
                AppTheme.bgCard
                LinearGradient(
                    colors: [AppTheme.orange.opacity(0.14), .clear],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private var modeDescriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("О режиме")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Камера отслеживает траекторию мяча и положение рук в кадре, автоматически подсчитывая ключевые показатели дриблинга.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(icon: "arrow.down.to.line", color: AppTheme.orange, text: "Удары, темп (уд/с) и средняя высота отскока")
                infoRow(icon: "hand.raised.fill", color: AppTheme.mint, text: "Контроль мяча, потери и броски")
                infoRow(icon: "iphone.rear.camera", color: AppTheme.blue, text: "Поставьте телефон на расстоянии 2–3 м, чтобы быть в полный рост")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkCard(cornerRadius: 20, padding: 18)
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22)
                .padding(.top, 1)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}

// MARK: - Экран 2: Live Camera HUD

struct CameraWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    let showDebugHUD: Bool

    @StateObject private var session: CameraSessionStore
    @State private var finishedRecord: WorkoutRecord?
    @State private var shouldDismissWorkout = false

    init(showSkeleton: Bool, showBallBox: Bool, showDebugHUD: Bool) {
        self.showDebugHUD = showDebugHUD
        _session = StateObject(wrappedValue: CameraSessionStore(showSkeleton: showSkeleton, showBallBox: showBallBox))
    }

    var body: some View {
        ZStack {
            CameraPreviewRepresentable(session: session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, Color.black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 250)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                topHUD
                Spacer()
                if session.isPaused && finishedRecord == nil {
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
            if shouldDismissWorkout {
                session.stop()
                DispatchQueue.main.async {
                    dismiss()
                }
            } else {
                session.setPaused(false)
            }
        }) { record in
            WorkoutSummaryView(
                record: record,
                onSave: {
                    store.save(record)
                    shouldDismissWorkout = true
                    finishedRecord = nil
                },
                onDiscard: {
                    shouldDismissWorkout = true
                    finishedRecord = nil
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    private var topHUD: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isPaused ? Color.yellow : AppTheme.red)
                        .frame(width: 8, height: 8)
                    Text(session.formattedElapsed)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                if showDebugHUD {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 14)

                    Text(String(format: "%.0f FPS", session.fps))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(session.fps >= 24 ? AppTheme.mint : .yellow)

                    Text(session.modelStatus)
                        .font(.caption2.weight(.semibold))
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

            GlassCircleButton(icon: "figure.walk", isActive: session.showSkeleton) {
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
            Text("Пауза")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.yellow.opacity(0.4), lineWidth: 1))
    }

    private var bottomHUD: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Удары")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.orangeLight)

                        Text("\(session.metrics.realBounces)")
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.white)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: session.metrics.realBounces)
                    }
                    .frame(minWidth: 92, alignment: .leading)

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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )

            HStack(spacing: 14) {
                GlassCircleButton(icon: "arrow.counterclockwise", size: 52) {
                    session.reset()
                }

                Button {
                    session.togglePause()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        Text(session.isPaused ? "Продолжить" : "Пауза")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        session.isPaused
                            ? AppTheme.orangeGradient
                            : LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    session.setPaused(true)
                    finishedRecord = session.buildRecord()
                } label: {
                    Text("Финиш")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 52)
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
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.caption.weight(.semibold))
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
                .fill(Color.white.opacity(0.22))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.orange.opacity(0.16))
                        .frame(width: 68, height: 68)
                    Image(systemName: "trophy.fill")
                        .font(.title)
                        .foregroundStyle(AppTheme.orangeGradient)
                }

                Text("Тренировка завершена")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Свободный дриблинг · \(record.formattedDuration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summaryBox(title: "Удары", value: "\(record.realBounces)", color: AppTheme.orange)
                summaryBox(title: "Темп", value: String(format: "%.2f уд/с", record.tempo), color: AppTheme.mint)
                summaryBox(title: "Ср. высота", value: String(format: "%.1f см", record.avgHeightCm), color: AppTheme.blue)
                summaryBox(title: "Броски / Потери", value: "\(record.shots) / \(record.falseBounces)", color: .white)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Контроль мяча")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(record.controlPercent)%")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.mint)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(AppTheme.mint)
                            .frame(width: geo.size.width * CGFloat(record.controlPercent) / 100.0)
                    }
                }
                .frame(height: 8)
            }
            .darkCard(cornerRadius: 16, padding: 16)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onSave) {
                    Text("Сохранить в историю")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.orangeGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDiscard) {
                    Text("Удалить сессию")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.red)
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
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkCard(cornerRadius: 16, padding: 14)
    }
}

// MARK: - Экран 4: Удобная история тренировок

enum HistorySortOption: String, CaseIterable, Identifiable {
    case newest = "Сначала новые"
    case mostBounces = "Больше ударов"
    case fastestTempo = "Выше темп"

    var id: String { rawValue }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var sortOption: HistorySortOption = .newest
    @State private var selectedRecord: WorkoutRecord?

    private var sortedHistory: [WorkoutRecord] {
        switch sortOption {
        case .newest:
            return store.history.sorted { $0.date > $1.date }
        case .mostBounces:
            return store.history.sorted { $0.realBounces > $1.realBounces }
        case .fastestTempo:
            return store.history.sorted { $0.tempo > $1.tempo }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    emptyStateView
                } else {
                    List {
                        Section {
                            HStack(spacing: 0) {
                                overviewItem(title: "Тренировки", value: "\(store.history.count)", color: .white)
                                Divider().frame(height: 28)
                                overviewItem(title: "Всего ударов", value: "\(store.totalBounces)", color: AppTheme.orange)
                                Divider().frame(height: 28)
                                overviewItem(title: "Ср. контроль", value: "\(store.averageControl)%", color: AppTheme.mint)
                            }
                            .padding(.vertical, 6)
                        }

                        Section("Тренировки") {
                            ForEach(sortedHistory) { record in
                                Button {
                                    selectedRecord = record
                                } label: {
                                    HistoryRow(record: record)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            store.delete(record)
                                        }
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("История")
            .toolbar {
                if !store.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Сортировка", selection: $sortOption) {
                                ForEach(HistorySortOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .foregroundStyle(AppTheme.orange)
                        }
                    }
                }
            }
            .sheet(item: $selectedRecord) { record in
                WorkoutDetailSheet(record: record) {
                    store.delete(record)
                    selectedRecord = nil
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "basketball")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)

            Text("Пока нет тренировок")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("Завершите первую тренировку и нажмите «Сохранить», чтобы отслеживать свой прогресс.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bgPrimary.ignoresSafeArea())
    }

    private func overviewItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.formattedDate)
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Label(record.formattedDuration, systemImage: "clock")
                    Text("·")
                    Text("Контроль \(record.controlPercent)%")
                        .foregroundStyle(AppTheme.mint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(record.realBounces) уд.")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(String(format: "%.2f уд/с", record.tempo))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.orangeLight)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct WorkoutDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: WorkoutRecord
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Основное") {
                    LabeledContent("Дата", value: record.formattedDate)
                    LabeledContent("Длительность", value: record.formattedDuration)
                }

                Section("Показатели") {
                    LabeledContent("Удары") {
                        Text("\(record.realBounces)")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.orange)
                    }
                    LabeledContent("Темп") {
                        Text(String(format: "%.2f уд/с", record.tempo))
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.mint)
                    }
                    LabeledContent("Средняя высота отскока") {
                        Text(String(format: "%.1f см", record.avgHeightCm))
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.blue)
                    }
                    LabeledContent("Контроль мяча") {
                        Text("\(record.controlPercent)%")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.mint)
                    }
                    LabeledContent("Броски", value: "\(record.shots)")
                    LabeledContent("Потери", value: "\(record.falseBounces)")
                }

                Section {
                    Button(role: .destructive, action: onDelete) {
                        HStack {
                            Spacer()
                            Text("Удалить тренировку")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Детали сессии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Экран 5: Настройки

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Отображение на камере") {
                    Toggle("Скелет игрока (Vision)", isOn: $store.showSkeleton)
                        .tint(AppTheme.orange)
                    Toggle("Рамка мяча (YOLO)", isOn: $store.showBallBox)
                        .tint(AppTheme.orange)
                    Toggle("FPS и статус модели", isOn: $store.showDebugHUD)
                        .tint(AppTheme.orange)
                }

                Section {
                    Picker("Размер мяча", selection: $store.ballSize) {
                        ForEach(BallSizeOption.allCases) { size in
                            Text("\(size.title) (\(Int(size.diameterCm)) см)").tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Калибровка мяча")
                } footer: {
                    Text("Используется для пересчёта высоты отскока в сантиметры.")
                }
            }
            .navigationTitle("Настройки")
        }
    }
}       