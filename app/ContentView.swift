import SwiftUI

#if os(iOS)
import UIKit

struct ContentView: View {
    let settings: ConnectionSettings

    private enum Field { case service, key }

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focus: Field?
    @State private var serviceID = ""
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var deletionTarget: CredentialRegistration?
    @State private var confirmingDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    brandMark
                    Text("microDrop")
                        .font(.largeTitle.bold())
                }
                .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 20) {
                    Text("microCMSの接続設定")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    switch settings.state {
                    case .loading:
                        ProgressView("設定を読み込み中…")
                    case .empty:
                        registrationForm
                    case .registered(let registration):
                        savedConnection(registration)
                    case .unavailable(let reason):
                        Text(verbatim: reason)
                        Button("読み込み直す") { Task { await settings.refresh() } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("写真から送る", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    SharingSteps(photoSelection: "「写真」で画像を1枚選ぶ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .task { await settings.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await settings.refresh() } }
            if phase == .background { apiKey = "" }
        }
        .onChange(of: settings.hasRegistration) { _, _ in
            clearForm()
        }
        .alert("この端末の接続設定を削除しますか？", isPresented: $confirmingDeletion,
               presenting: deletionTarget) { registration in
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    do {
                        try await settings.delete(registration)
                        clearForm()
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        } message: { registration in
            Text("「\(registration.serviceID)」のサービスIDとAPIキーを端末から削除します。再びアップロードするには登録が必要です。")
        }
    }

    private var brandMark: some View {
        Group {
            if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let name = (primary["CFBundleIconFiles"] as? [String])?.last,
               let image = UIImage(named: name) {
                Image(uiImage: image).resizable()
            } else {
                ZStack {
                    Color(white: 0.15)
                    Image(systemName: "drop.fill").font(.title).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private var registrationForm: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("サービスID").font(.subheadline.weight(.semibold))
                TextField("例：my-service", text: $serviceID)
                    .accessibilityLabel("サービスID")
                    .focused($focus, equals: .service)
                    .submitLabel(.next)
                    .onSubmit { focus = .key }
                    .modifier(ConnectionFieldStyle())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("APIキー").font(.subheadline.weight(.semibold))
                SecureField("APIキーを入力", text: $apiKey)
                    .accessibilityLabel("APIキー")
                    .focused($focus, equals: .key)
                    .submitLabel(.done)
                    .onSubmit { if canRegister { register() } }
                    .privacySensitive()
                    .modifier(ConnectionFieldStyle())
                Text("「メディアのアップロード」権限を有効にしたAPIキーを使用します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            errorNotice
            PrimaryActionButton(title: settings.isSaving ? "登録中…" : "接続設定を登録",
                                systemImage: "lock.fill", isBusy: settings.isSaving) { register() }
                .disabled(!canRegister)
            Text("設定はこの端末のキーチェーンに保存します。変更するには削除してから再登録してください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func savedConnection(_ registration: CredentialRegistration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("サービスID").font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: registration.serviceID)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
        }
        Divider()
        LabeledContent("APIキー") {
            Label("登録済み", systemImage: "lock.fill")
        }
        errorNotice
        Button(role: .destructive) {
            deletionTarget = registration
            confirmingDeletion = true
        } label: {
            Label("接続設定を削除", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(settings.isSaving)
    }

    @ViewBuilder
    private var errorNotice: some View {
        if let errorMessage {
            Label {
                Text(verbatim: errorMessage)
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.red)
        }
    }

    private var canRegister: Bool {
        !serviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !settings.isSaving
    }

    private func register() {
        guard canRegister else { return }
        focus = nil
        errorMessage = nil
        let service = serviceID, key = apiKey
        Task {
            do {
                try await settings.register(serviceID: service, apiKey: key)
                clearForm()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func clearForm() {
        focus = nil
        serviceID = ""
        apiKey = ""
        errorMessage = nil
    }
}

private struct ConnectionFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
#else
struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "square.and.arrow.up")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("写真をmicroCMSに送る")
                .font(.title.bold())
            SharingSteps(photoSelection: "iPhoneの「写真」で画像を1枚選ぶ")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding()
    }
}
#endif

private struct SharingSteps: View {
    let photoSelection: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            step(1, photoSelection)
            step(2, "共有メニューで「microDrop」を開く")
            step(3, "「microCMSにアップロード」をタップ")
        }
    }

    private func step(_ number: Int, _ instruction: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).")
            Text(instruction)
        }
        .accessibilityElement(children: .combine)
    }
}
