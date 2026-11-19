import Foundation

struct MicroCMSClient {
    let credentials: MicroCMSCredentials
    private let session: URLSession

    init(credentials: MicroCMSCredentials, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.credentials = credentials
        self.session = session
    }

    func upload(_ image: ImageAttachment) async throws -> URL {
        guard let endpoint = URL(string: "https://\(credentials.serviceID).microcms-management.io/api/v1/media") else {
            throw UploadError.invalidService
        }
        guard !image.data.isEmpty, image.data.count < ImageAttachment.uploadSizeLimit else {
            throw UploadError.invalidImageSize
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let safeName = Self.uploadFilename(image.filename, format: image.format)
        var body = Data("--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: \(image.format.mimeType)\r\n\r\n".utf8)
        body.append(image.data)
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-MICROCMS-API-KEY")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body, delegate: RedirectBlocker())
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            switch error.code {
            case .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
                throw UploadError.cannotConnect
            default:
                throw UploadError.unknownOutcome
            }
        } catch {
            try Task.checkCancellation()
            throw UploadError.unknownOutcome
        }

        guard let response = response as? HTTPURLResponse else { throw UploadError.unknownOutcome }
        switch response.statusCode {
        case 201:
            struct Receipt: Decodable { let url: String }
            guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
                  let url = URLComponents(string: receipt.url),
                  url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, let mediaURL = url.url else {
                throw UploadError.missingURL
            }
            return mediaURL
        case 300..<400: throw UploadError.redirect
        case 400: throw UploadError.badRequest
        case 401, 403: throw UploadError.unauthorized
        case 413: throw UploadError.invalidImageSize
        case 429: throw UploadError.rateLimited
        case 200..<300, 500..<600: throw UploadError.unknownOutcome
        default: throw UploadError.rejected(response.statusCode)
        }
    }

    private static func uploadFilename(_ filename: String, format: ImageFormat) -> String {
        let stem = (filename as NSString).lastPathComponent as NSString
        let safe = stem.deletingPathExtension.utf8.prefix(100).map { byte -> UInt8 in
            switch byte {
            case 65...90, 97...122, 48...57, 45, 95: return byte
            default: return 95
            }
        }
        return (safe.isEmpty ? "image" : String(decoding: safe, as: UTF8.self)) + "." + format.filenameExtension
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                                completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum UploadError: LocalizedError {
    case invalidService, invalidImageSize, cannotConnect, unknownOutcome, missingURL
    case redirect, badRequest, unauthorized, rateLimited, rejected(Int)

    var errorDescription: String? {
        switch self {
        case .invalidService: "設定したmicroCMSのサービスIDを確認してください。"
        case .invalidImageSize: "画像は空でなく、5MB未満である必要があります。"
        case .cannotConnect: "microCMSに接続できません。通信環境とサービスIDを確認してください。"
        case .unknownOutcome: "登録結果を確認できません。再送前にmicroCMSのメディア一覧を確認してください。"
        case .missingURL: "登録に成功しましたが、画像URLを取得できませんでした。メディア一覧を確認してください。"
        case .redirect: "アップロード先がリダイレクトを返しました。サービスIDを確認してください。"
        case .badRequest: "画像を受け付けられませんでした。画像サイズや送信形式を確認してください（400）。"
        case .unauthorized: "APIキーと「メディアのアップロード」権限を確認してください。"
        case .rateLimited: "リクエストの上限に達しました。しばらく待ってから再送してください（429）。"
        case .rejected(let status): "microCMSがアップロードを受け付けませんでした（HTTP \(status)）。"
        }
    }
}
