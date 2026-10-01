import SwiftUI

struct EULAView: View {
    @EnvironmentObject private var model: AppModel
    @State private var hasReachedEnd = false
    @State private var agreed = false
    @State private var showPrivacy = false

    private let sections: [(String, String)] = [
        ("1. Independent, unofficial software", "eForms is independently developed. It is not affiliated with, endorsed by, authorised by, sponsored by or published by the University of Manchester, its eForms service, or any associated organisation. Names and service addresses belonging to third parties are used only to identify compatibility and remain their owners’ property."),
        ("2. Eligibility and account authority", "You may use the app only if you are at least 18, have a valid eligible account, and are authorised to access every form and record you use. You are responsible for complying with your institution’s rules, placement requirements, professional obligations and the connected service’s terms."),
        ("3. Limited licence", "The Developer grants a limited, personal, non-exclusive, non-transferable, revocable licence for lawful non-commercial form work. You must not sell, sublicense, misrepresent, maliciously modify, circumvent security, interfere with the service, attempt unauthorised access, or violate law or third-party rights."),
        ("4. Third-party service", "The app is a client for a third-party service. The Developer does not control that service, its authentication, availability, data, retention, security or changes. Access may stop if the service, its interfaces, policies or your account changes."),
        ("5. Offline work, drafts and submissions", "Offline storage, synchronisation, draft upload and Outbox retry are convenience features, not guarantees. A local Saved, Sent or Outbox label is not proof that the service received, accepted or retained a form. Reconnect, refresh and verify important submissions in the official service."),
        ("6. Clinical and academic use", "The app is an administrative form tool. It does not provide medical, clinical, legal, academic or professional advice; it is not an authoritative clinical record; and it must not replace supervision, local procedures or professional judgement."),
        ("7. Your content and confidentiality", "You retain rights in content you lawfully enter. You permit the app to store, encrypt, display and transmit it only as needed to provide its features. You must have authority and any necessary consent to process personal or confidential information."),
        ("8. Privacy and security", "The Privacy Policy forms part of these terms. The app uses reasonable safeguards, including encrypted local storage, but no device, software or transmission is completely secure. Technical crash reports must not deliberately include form answers, signatures, credentials or usernames."),
        ("9. Updates and termination", "The Developer may update, change, suspend or discontinue the app or its compatibility. You may end this licence by logging out, removing local data and uninstalling the app."),
        ("10. Software provided as is", "To the fullest extent permitted by law, the app is supplied ‘as is’ and ‘as available’, without promises that it will be uninterrupted, error-free, secure, compatible, accurate, complete or fit for a particular purpose. Mandatory legal rights remain unaffected."),
        ("11. Liability", "Nothing excludes liability that cannot lawfully be excluded. Subject to that, the Developer is not liable for indirect or consequential loss, lost data, missed deadlines, academic or placement consequences, service outages, unauthorised account use, or acts and omissions of the service owner."),
        ("12. Responsibility for misuse", "To the extent permitted by law, you are responsible for reasonable losses directly caused by deliberate unlawful use, unauthorised access, infringement of another person’s rights, or material breach of these terms."),
        ("13. Governing law", "These terms are governed by the laws of England and Wales. Mandatory consumer protections and any right to bring proceedings in your home jurisdiction are unaffected."),
        ("14. General terms", "If a provision is unlawful or unenforceable, it will be limited or removed only as necessary and the remaining terms continue. Material changes will be presented for renewed acceptance.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("eForms").foregroundStyle(Color(red: 222/255, green: 195/255, blue: 236/255))
                Text("End User Licence Agreement").font(.title2).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.deep)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Please read before using the app").font(.title3.weight(.semibold))
                    Text("Effective 22 September 2026 • EULA version 1").font(.caption).foregroundStyle(AppTheme.muted)
                    Text("This End User Licence Agreement is between you and the developer or publisher identified in the app’s store listing. By accepting, you agree to these terms. If you do not agree, do not use the app.")
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Text(section.0).font(.headline).foregroundStyle(AppTheme.deep).padding(.top, 5)
                        Text(section.1).font(.body)
                    }
                    Text("End of EULA").font(.caption).foregroundStyle(AppTheme.muted)
                        .onAppear { hasReachedEnd = true }
                }
                .padding(18)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(hasReachedEnd ? "You can now accept the agreement" : "Scroll to the end to enable acceptance")
                    .font(.caption).foregroundStyle(AppTheme.muted)
                Toggle("I have read and accept the EULA", isOn: $agreed).disabled(!hasReachedEnd)
                HStack {
                    Button("Privacy") { showPrivacy = true }.buttonStyle(CompactButtonStyle(primary: false))
                    Spacer()
                    Button("Accept and continue") { model.acceptEULA() }
                        .buttonStyle(CompactButtonStyle(primary: true))
                        .disabled(!agreed)
                }
            }
            .padding(14)
            .background(Color(red: 247/255, green: 245/255, blue: 248/255))
        }
        .sheet(isPresented: $showPrivacy) { NavigationStack { PrivacyView() } }
    }
}

