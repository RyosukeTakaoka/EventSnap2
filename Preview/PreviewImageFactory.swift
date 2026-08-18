//
//  PreviewImageFactory.swift
//  EventSnap
//
//  Fixture写真の実体を用意する（実写があればそれを、無ければ決定論的に生成）。
//

#if DEBUG

import Foundation
import UIKit

/// Fixtureの写真をローカルの`file://`として用意する。
///
/// ## なぜファイルに書き出すのか
///
/// `Photo.imageURL` / `thumbnailURL` はCloudKitの`CKAsset.fileURL`（＝`file://`）が
/// 入るフィールドであり、`PhotoImageLoader`は`URLSession.data(from:)`で読む。
/// 同じ形のローカルURLを入れれば、**画像取得の本番コードを一切変更せずに**
/// Fixture画像を流し込める。これが本設計の要。
///
/// ## 実写の差し替え
///
/// `preview-photo-01.jpg` … `preview-photo-18.jpg` という名前のJPEGを
/// アプリターゲットのリソースとして追加すると、生成画像より優先して使われる
/// （詳細は `Preview/Fixtures/README.md`）。
/// 見つからない番号は手続き生成のプレースホルダで埋める。
@MainActor
enum PreviewImageFactory {

    /// 生成ロジックを変えたらここを上げる。古いキャッシュを無視して作り直される。
    private static let version = 3

    /// アルバムのグリッド・写真詳細・Event Reelの描画に十分な解像度。
    /// 本番のアップロードは最大1920pxだが、撮影用にそこまでは要らない
    /// （18枚すべてをメモリに載せるとフットプリントが無駄に大きくなる）。
    private static let fullSize = CGSize(width: 900, height: 1200)
    private static let thumbnailSize = CGSize(width: 300, height: 400)

    struct Materialized {
        let imageURLs: [URL]
        let thumbnailURLs: [URL]
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EventSnapPreviewFixtures/v\(version)", isDirectory: true)
    }

    private static func fullURL(_ index: Int) -> URL {
        directory.appendingPathComponent(String(format: "photo-%02d.jpg", index))
    }

    private static func thumbnailURL(_ index: Int) -> URL {
        directory.appendingPathComponent(String(format: "thumb-%02d.jpg", index))
    }

    // MARK: - 用意する

    /// `count`枚分の画像をディスク上に用意し、そのURLを返す。
    /// 既に揃っていれば再生成しない（2回目以降の起動は即座に立ち上がる）。
    static func materialize(count: Int) -> Materialized {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var imageURLs: [URL] = []
        var thumbnailURLs: [URL] = []

        for index in 0..<count {
            let full = fullURL(index)
            let thumb = thumbnailURL(index)

            if !FileManager.default.fileExists(atPath: full.path)
                || !FileManager.default.fileExists(atPath: thumb.path) {
                let source = bundledPhoto(index: index) ?? placeholder(index: index, size: fullSize)
                write(resize(source, to: fullSize), to: full, quality: 0.9)
                write(resize(source, to: thumbnailSize), to: thumb, quality: 0.8)
            }

            imageURLs.append(full)
            thumbnailURLs.append(thumb)
        }

        return Materialized(imageURLs: imageURLs, thumbnailURLs: thumbnailURLs)
    }

    /// 生成済みの画像を1枚読み込む（Event Reelの描画・カメラ背景に使う）。
    static func loadImage(at index: Int) -> UIImage? {
        UIImage(contentsOfFile: fullURL(index).path)
    }

    /// 作り直したいときに呼ぶ（現状はデバッグ用。通常の撮影フローでは使わない）。
    static func reset() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 実写の取り込み

    private static func bundledPhoto(index: Int) -> UIImage? {
        bundledImage(named: String(format: "preview-photo-%02d", index + 1))
    }

    /// カメラ背景専用の実写（`preview-camera-bg.jpg`）を読み込む。
    ///
    /// 見つからなければ`nil`を返す。呼び出し側（`PreviewFixtureLoader`）が
    /// 通常のFixture写真へフォールバックする。
    static func bundledCameraBackground() -> UIImage? {
        bundledImage(named: "preview-camera-bg")
    }

    /// QR読み取りファインダー背景専用の実写（`preview-qrscan-bg.jpg`）を読み込む。
    /// 見つからなければ`nil`を返す。
    static func bundledQRScanBackground() -> UIImage? {
        bundledImage(named: "preview-qrscan-bg")
    }

    /// アプリバンドルから`name`.jpg/.jpeg/.pngのいずれかを探して読み込む。
    private static func bundledImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg")
                ?? Bundle.main.url(forResource: name, withExtension: "jpeg")
                ?? Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    // MARK: - プレースホルダ生成

    /// `index`だけから決まる疑似乱数（xorshift64）。
    /// `Double.random`を使わないことで、何度起動しても同じ絵になる。
    private struct Seeded {
        private var state: UInt64

        init(seed: Int) {
            let mixed = UInt64(truncatingIfNeeded: seed) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            state = mixed | 1
        }

        mutating func unit() -> CGFloat {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return CGFloat(state % 10_000) / 10_000
        }

        mutating func range(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            lower + unit() * (upper - lower)
        }
    }

    /// 実写が無いときのプレースホルダ。
    ///
    /// **App Store提出前には必ず実写に差し替えること。** ここで文字やロゴを
    /// 描かないのは、サムネイルサイズで「写真の代わり」として自然に見える
    /// 抽象的な絵にしたいため（ラベル入りの画像は明らかに作り物に見える）。
    private static func placeholder(index: Int, size: CGSize) -> UIImage {
        var rng = Seeded(seed: index &+ 7)

        let baseHue = CGFloat((index &* 37) % 360) / 360
        let secondHue = baseHue + rng.range(0.06, 0.18)

        let top = UIColor(hue: baseHue, saturation: rng.range(0.42, 0.58),
                          brightness: rng.range(0.86, 0.96), alpha: 1)
        let bottom = UIColor(hue: secondHue.truncatingRemainder(dividingBy: 1),
                             saturation: rng.range(0.55, 0.72),
                             brightness: rng.range(0.42, 0.60), alpha: 1)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext

            // 斜めのグラデーション
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [top.cgColor, bottom.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            } else {
                top.setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }

            // やわらかい光の玉。写真のボケに近い印象を作る。
            for _ in 0..<5 {
                let radius = rng.range(size.width * 0.10, size.width * 0.34)
                let center = CGPoint(
                    x: rng.range(-radius * 0.4, size.width + radius * 0.4),
                    y: rng.range(-radius * 0.4, size.height + radius * 0.4)
                )
                let alpha = rng.range(0.06, 0.16)
                UIColor(white: 1, alpha: alpha).setFill()
                cg.fillEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                ))
            }

            // 下端をわずかに落として、写真らしい奥行きを付ける
            if let vignette = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 0, alpha: 0).cgColor,
                         UIColor(white: 0, alpha: 0.22).cgColor] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    vignette,
                    start: CGPoint(x: 0, y: size.height * 0.55),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
        }
    }

    // MARK: - 入出力

    private static func resize(_ image: UIImage, to target: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // アスペクト比を保ったまま中央でカバーする（本番のグリッドと同じ見え方）
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (target.width - drawSize.width) / 2,
                y: (target.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    private static func write(_ image: UIImage, to url: URL, quality: CGFloat) {
        guard let data = image.jpegData(compressionQuality: quality) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

#endif
