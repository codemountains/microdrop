# microDrop

## microCMS Media Share Extension

iOS 17以降の共有メニューから画像を1枚選び、microCMSにアップロードできます。対応形式は JPEG、PNG、GIF、WebP、HEIC、HEIF です。

## サービスを登録する

microDropを開き、サービスIDと「メディアのアップロード」権限があるmicroCMSのAPIキーを入力して登録します。サービスIDは `https://my-blog.microcms.io` の場合、`my-blog` です。旧バージョンで `Secrets.swift` を使っていた場合も、更新後の初回にアプリで登録してください。

登録後はサービスIDを確認できます。接続先やキーを変更するときは、登録を削除して新しく登録します。アプリでの削除はこの端末の登録にのみ適用されます。キー自体の失効はmicroCMSの管理画面で行えます。

## 保存と共有

サービスIDとAPIキーを1件の汎用パスワードとしてKeychainに保存します。端末のロック解除中にアクセスできる `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` を使い、iCloudキーチェーン同期を無効にしています。本体と共有拡張は同じKeychainアクセスグループを使います。本体の登録済み画面はサービスIDだけを読み、共有拡張は送信時にキーを取得します。

## Xcodeからインストールする

1. Xcode 27.2 で `microDrop.xcodeproj` を開きます。Apple Account を追加していない場合は、**Xcode > Settings > Apple Accounts** で追加します。
2. Project Navigator で `microDrop` プロジェクトを開き、**PROJECT** の `microDrop` を選択します。**Build Settings** で **All** を選び、`HOST_APP_BUNDLE_IDENTIFIER` を検索して、自分の一意なバンドルID（例 `com.yourname.microdrop`）を設定します。共有拡張のバンドルIDには、本体のIDの末尾に `.ShareExtension` が付きます。
3. **TARGETS** の `microDrop` と `ShareExtension` それぞれで **Signing & Capabilities** を開きます。**Automatically manage signing** を有効にし、両方の **Team** に自分の同じ署名チームを選択します。両ターゲットは `Keychain.entitlements` で同じ Keychain アクセスグループを使います。
4. `microDrop` スキームと接続した iPhone を選び、**Run**（⌘R）でインストールします。

## 画像を送る

「写真」などで画像を1枚開き、共有メニューの「microDrop」を選びます。初回は共有先を横にスクロールし、「その他」を開くと見つかります。プレビューを確認して「microCMSにアップロード」を押し、結果が出るまで画面を開いておきます。「URLをコピー」を押してから「完了」で閉じます。

送信する画像は5 MB未満です。JPEGは5 MB未満に収まるよう圧縮します。PNG、GIF、WebP、HEIC、HEIFは共有元から受け取ったデータをそのまま送るため、透過やアニメーション、撮影メタデータが保持されます。
