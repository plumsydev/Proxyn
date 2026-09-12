import SwiftUI

/// Launch sequence: the mark draws itself, then the view dissolves into the
/// app. About a second, skippable with a tap, instant with Reduce Motion.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var progress: Double = 0
    @State private var titleVisible = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 18) {
                ProxynMark(size: 76, progress: progress)
                Text("Proxyn")
                    .font(.title2.weight(.semibold))
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proxyn")
    }

    private func run() async {
        guard !reduceMotion else {
            progress = 1
            titleVisible = true
            try? await Task.sleep(for: .milliseconds(250))
            finish()
            return
        }
        withAnimation(.easeInOut(duration: 0.7)) { progress = 1 }
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.smooth(duration: 0.35)) { titleVisible = true }
        try? await Task.sleep(for: .milliseconds(520))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
