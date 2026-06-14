import SwiftUI

struct LoadingScreenView: View {
    @Environment(VideoRepository.self) private var repository
    var onDismiss: () -> Void

    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @Environment(LoadingSoundPlayer.self) private var soundPlayer
    @State private var logoRotation: Double = 0
    @State private var isExiting = false
    @State private var appearDate = Date()
    @State private var dismissed = false
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var showSlowHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A threshold, not a wait: gone the instant data is ready, with just enough
    // floor to avoid a flash. (Was 2.5s — which forced a wait the theme forbids.)
    private let minimumDisplayTime: TimeInterval = 0.6
    private let maxTimeout: TimeInterval = 10.0

    var body: some View {
        ZStack {
            Color.black
                .overlay(Color.dumpiGreenDark.opacity(0.05))
                .ignoresSafeArea()
                .opacity(isExiting ? 0 : 1)

            Image("dumpert-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 280)
                .rotationEffect(.degrees(logoRotation))
                .scaleEffect(exitScale)
                .opacity(isExiting ? 0 : logoOpacity)

            // Only appears if the load is genuinely slow — the happy path never
            // sees it, so the threshold stays pure under good conditions.
            if showSlowHint && !isExiting {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Menu om over te slaan", comment: "Loading screen: hint to skip with the Menu button")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 120)
                .transition(.opacity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Dumpert wordt geladen", comment: "Accessibility label shown while the app is loading"))
        .focusable()
        .onExitCommand {
            performExit()
        }
        .onAppear {
            appearDate = Date()
            startLogoAnimation()
            soundPlayer.playRandom()
            startTimeout()
            startSlowHintTimer()
        }
        .onChange(of: repository.isLoading) { _, isLoading in
            if !isLoading {
                Task { @MainActor in
                    scheduleExit()
                }
            }
        }
    }

    private func startLogoAnimation() {
        // Reduce Motion: a calm fade-in, no spring overshoot and no heartbeat.
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            return
        }

        withAnimation(.spring(duration: 1.2, bounce: 0.3)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Start heartbeat after intro animation completes
        heartbeatTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, !dismissed else { return }
            await startHeartbeat()
        }
    }

    private func startHeartbeat() async {
        // Realistic heartbeat: two quick beats ("lub-dub") then a pause
        while !Task.isCancelled && !dismissed {
            // First beat (lub) — quick strong pump
            withAnimation(.easeOut(duration: 0.12)) {
                heartbeatScale = 1.12
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeIn(duration: 0.10)) {
                heartbeatScale = 0.92
            }
            try? await Task.sleep(for: .milliseconds(100))

            // Second beat (dub) — slightly softer
            withAnimation(.easeOut(duration: 0.12)) {
                heartbeatScale = 1.06
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeIn(duration: 0.15)) {
                heartbeatScale = 0.85
            }
            try? await Task.sleep(for: .milliseconds(150))

            // Relax back to normal
            withAnimation(.easeOut(duration: 0.20)) {
                heartbeatScale = 1.0
            }
            try? await Task.sleep(for: .milliseconds(200))

            // Pause between heartbeats
            try? await Task.sleep(for: .milliseconds(400))

            guard !Task.isCancelled, !dismissed else { break }
        }
    }

    private func startTimeout() {
        Task {
            try? await Task.sleep(for: .seconds(maxTimeout))
            guard !dismissed else { return }
            performExit()
        }
    }

    /// Surfaces a progress indicator + skip hint only once the load is clearly
    /// slow, so a fast launch never shows them.
    private func startSlowHintTimer() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !dismissed, !isExiting else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) {
                showSlowHint = true
            }
        }
    }

    /// Exit zoom: a 50× burst normally, but flat under Reduce Motion so the exit
    /// is a clean cross-fade instead of a zoom-bomb.
    private var exitScale: CGFloat {
        if isExiting { return reduceMotion ? 1.0 : 50.0 }
        return logoScale * heartbeatScale
    }

    private func scheduleExit() {
        guard !dismissed else { return }
        Task {
            let elapsed = Date().timeIntervalSince(appearDate)
            if elapsed < minimumDisplayTime {
                try? await Task.sleep(for: .seconds(minimumDisplayTime - elapsed))
            }
            performExit()
        }
    }

    private func performExit() {
        guard !dismissed else { return }
        dismissed = true
        heartbeatTask?.cancel()
        heartbeatScale = 1.0

        // Reduce Motion: a plain cross-fade out — no 50× zoom-bomb, no rotation.
        if reduceMotion {
            withAnimation(.easeIn(duration: 0.4)) {
                isExiting = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                onDismiss()
            }
            return
        }

        logoRotation = Double.random(in: -25...25)
        withAnimation(.easeIn(duration: 0.6)) {
            isExiting = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            onDismiss()
        }
    }
}
