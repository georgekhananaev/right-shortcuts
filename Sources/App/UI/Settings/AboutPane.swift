import AppKit
import RightShortcutsCore
import SwiftUI

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text(AppIdentity.displayName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("The actions you use most, one right-click away in Finder.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 4)
            HStack(spacing: 20) {
                Link("Privacy Policy", destination: AppIdentity.privacyPolicyURL)
                Link("Support", destination: AppIdentity.supportURL)
            }
            .padding(.top, 6)
            Spacer()
            Text("Made by George Khananaev")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
