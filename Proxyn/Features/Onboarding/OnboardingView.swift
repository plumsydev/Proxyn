import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddServer = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ProxynMark(size: 72)
                VStack(spacing: 8) {
                    Text("Proxyn")
                        .font(.largeTitle.weight(.semibold))
                    Text("Monitor and manage your Proxmox VE servers from your iPhone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 360)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    showAddServer = true
                } label: {
                    Text("Add Server")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Try the Demo") {
                    model.addServer(.demo())
                }
                .controlSize(.large)

                Text("Connects directly to your server. Credentials stay on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 400)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showAddServer) { AddServerView() }
    }
}
