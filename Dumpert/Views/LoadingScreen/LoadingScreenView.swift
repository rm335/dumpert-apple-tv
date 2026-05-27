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

    private let minimumDisplayTime: TimeInterval = 2.5
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
                .scaleEffect(isExiting ? 50.0 : logoScale * heartbeatScale)
                .opacity(isExiting ? 0 : logoOpacity)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Dumpert wordt geladen", comment: "Accessibility label shown while the app is loading"))
        .focusable()
        .onAppear {
            appearDate = Date()
            startLogoAnimation()
            soundPlayer.playRandom()
            startTimeout()
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
