import SwiftUI

/// Launch sequence: the mark strokes itself in, the rack units fill, the
/// wordmark settles, then the whole thing lifts a few points and dissolves as
/// the app fades up behind it. Under two seconds, and a tap skips it.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var markProgress: Double = 0
    @State private var wordProgress: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var isLeaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()

            VStack(spacing: 26) {
                ProxynMark(size: 88, progress: markProgress)

                VStack(spacing: 10) {
                    ProxynWordmark(progress: wordProgress, size: 25)
                    Text("Contrôle Proxmox")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkTertiary)
                        .opacity(taglineOpacity)
                }
            }
            .offset(y: isLeaving ? -10 : 0)
            .opacity(isLeaving ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish(immediate: true) }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proxyn, contrôle Proxmox")
    }

    private func run() async {
        if reduceMotion {
            markProgress = 1; wordProgress = 1; taglineOpacity = 1
            try? await Task.sleep(for: .milliseconds(420))
            finish(immediate: true)
            return
        }

        withAnimation(.easeInOut(duration: 0.95)) { markProgress = 1 }

        try? await Task.sleep(for: .milliseconds(560))
        withAnimation(.smooth(duration: 0.6)) { wordProgress = 1 }

        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeOut(duration: 0.45)) { taglineOpacity = 1 }

        try? await Task.sleep(for: .milliseconds(620))
        finish(immediate: false)
    }

    private func finish(immediate: Bool) {
        guard !isLeaving else { return }
        withAnimation(.easeIn(duration: immediate ? 0.22 : 0.38)) { isLeaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(immediate ? 200 : 340))
            onFinish()
        }
    }
}
