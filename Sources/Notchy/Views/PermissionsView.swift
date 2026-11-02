import Combine
import SwiftUI

/// First-launch onboarding that asks for each permission with a reason.
struct PermissionsOnboardingView: View {
    var onDone: () -> Void
    @EnvironmentObject private var permissions: PermissionsCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AppBadge(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to \(AppInfo.name)")
                        .font(.system(size: 20, weight: .bold))
                    Text("Allow what you'd like to use. Everything stays on this Mac.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            PermissionsList()
            HStack {
                Text("You can change these later in Customize › Permissions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button(permissions.requiredGranted ? "Done" : "Continue") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

struct PermissionsList: View {
    @EnvironmentObject private var permissions: PermissionsCenter
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            ForEach(PermissionsCenter.Kind.allCases) { kind in
                PermissionRow(kind: kind, status: permissions.status(kind)) {
                    permissions.request(kind)
                }
            }
        }
        // Grants made in System Settings don't post notifications, so poll while visible.
        .onReceive(poll) { _ in permissions.refresh() }
        .onAppear { permissions.refresh() }
    }
}

private struct PermissionRow: View {
    let kind: PermissionsCenter.Kind
    let status: PermissionsCenter.Status
    let action: () -> Void

    private var tint: Color {
        switch kind {
        case .calendar: return DS.Palette.events
        case .microphone: return DS.Palette.voice
        case .speech: return DS.Palette.focus
        case .screenRecording: return DS.Palette.clips
        case .reminders: return DS.Palette.tasks
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.system(size: 13, weight: .semibold))
                Text(kind.reason).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            switch status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("Allow", action: action)
            case .denied:
                Button("Open Settings", action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}
