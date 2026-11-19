import ImageIO
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(context: extensionContext))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: 440, height: 680)
    }
}

@MainActor
private struct ShareView: View {
    let context: NSExtensionContext?

    private enum Phase {
        case loading
        case ready(ImageAttachment, CredentialRegistration)
        case uploading
        case uploaded(URL)
        case failed(String)
    }

    private struct PhotoPreview {
        let image: CGImage
        let name: String
        let format: ImageFormat
        let byteCount: Int64
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var phase: Phase = .loading
    @State private var preview: PhotoPreview?
    @State private var copied = false
    @State private var uploadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if typeSize.isAccessibilitySize || verticalSizeClass == .compact {
                    ScrollView {
                        VStack(spacing: 20) {
                            previewContent(maxHeight: 270)
                            actions
                        }
                        .padding(20)
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        GeometryReader { space in
                            ScrollView {
                                previewContent(maxHeight: max(180, space.size.height - 24))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: 600)
                                    .frame(maxWidth: .infinity, minHeight: space.size.height)
                            }
                        }
                        actions
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                            .frame(maxWidth: 600)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("microDrop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .uploaded = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { context?.completeRequest(returningItems: nil) }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            uploadTask?.cancel()
                            context?.cancelRequest(withError: CocoaError(.userCancelled))
                        } label: {
                            Label("閉じる", systemImage: "xmark").labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .task { await prepare() }
        .onDisappear { uploadTask?.cancel() }
    }

    @ViewBuilder
    private func previewContent(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch phase {
            case .loading:
                ProgressView("画像を準備中…")
                    .frame(maxWidth: .infinity)
            case .failed(let message):
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                EmptyView()
            }
            if let image = preview?.image {
                PhotoStage(image: image)
                    .frame(height: maxHeight)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .ready(let photo, let registration):
                photoDetails
                PrimaryActionButton(title: "microCMSにアップロード", systemImage: "icloud.and.arrow.up.fill") {
                    upload(photo, to: registration)
                }
            case .uploading:
                photoDetails
                PrimaryActionButton(title: "アップロード中…", systemImage: "icloud.and.arrow.up.fill", isBusy: true) {}
            case .uploaded(let url):
                VStack(spacing: 6) {
                    Label("アップロード完了", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    Text(verbatim: url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                PrimaryActionButton(title: copied ? "コピーしました" : "URLをコピー",
                                  systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = url.absoluteString
                    copied = true
                }
            case .loading, .failed:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var photoDetails: some View {
        if let preview {
            VStack(spacing: 4) {
                Text(verbatim: preview.name)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(verbatim: preview.format.displayName + " · " + preview.byteCount.formatted(.byteCount(style: .file)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func prepare() async {
        guard case .loading = phase else { return }
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }
        guard attachments.count == 1, let provider = attachments.first else {
            phase = .failed("画像を1枚選んで共有してください。")
            return
        }
        do {
            let registration = try await Task.detached(priority: .userInitiated) {
                try CredentialStore.registration()
            }.value
            try Task.checkCancellation()
            guard let registration else {
                phase = .failed("microDropアプリでサービスIDとAPIキーを登録してから、画像をもう一度共有してください。")
                return
            }
            let photo = try await ImageAttachment.prepare(from: provider)
            let thumbnail = await Self.makeThumbnail(from: photo.data)
            try Task.checkCancellation()
            guard let thumbnail else {
                phase = .failed("画像を読み込めませんでした。")
                return
            }
            let name = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            preview = PhotoPreview(image: thumbnail, name: name.isEmpty ? "選択した画像" : name, format: photo.format,
                                   byteCount: Int64(photo.data.count))
            phase = .ready(photo, registration)
        } catch {
            if !Task.isCancelled { phase = .failed(error.localizedDescription) }
        }
    }

    private nonisolated static func makeThumbnail(from data: Data) async -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), options as CFDictionary)
    }

    private func upload(_ photo: ImageAttachment, to registration: CredentialRegistration) {
        guard case .ready = phase else { return }
        phase = .uploading
        uploadTask = Task {
            do {
                let credentials = try await Task.detached(priority: .userInitiated) {
                    try CredentialStore.credentials(for: registration)
                }.value
                try Task.checkCancellation()
                let client = MicroCMSClient(credentials: credentials)
                let url = try await client.upload(photo)
                phase = .uploaded(url)
            } catch {
                if Task.isCancelled {
                    phase = .failed("送信を中断しました。再送する前にmicroCMSのメディア一覧を確認してください。")
                } else {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }
}

private struct PhotoStage: View {
    let image: CGImage
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { space in
            let photo = Image(decorative: image, scale: 1).resizable()
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                if !reduceTransparency {
                    photo
                        .scaledToFill()
                        .frame(width: space.size.width, height: space.size.height)
                        .clipped()
                        .blur(radius: 24, opaque: true)
                        .overlay(.black.opacity(0.34))
                }
                photo
                    .scaledToFit()
                    .padding(12)
                    .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
            }
            .frame(width: space.size.width, height: space.size.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.primary.opacity(0.10)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共有する画像のプレビュー")
        .accessibilityAddTraits(.isImage)
    }
}
