//
//  UIImage+Orientation.swift
//  EventSnap
//

import UIKit

extension UIImage {

    /// `imageOrientation` を実際のピクセル配置に焼き込んで `.up` の画像にする。
    ///
    /// カメラが返す `UIImage` は、ピクセル自体はセンサーの並びのままで、
    /// 「どう回して表示するか」を `imageOrientation` に持っている。
    /// 表示するだけなら問題ないが、以下の処理は **orientation を無視する** ため
    /// 横向きの写真が崩れる原因になっていた。
    ///
    /// - `CIImage(image:)` … orientation を捨てて cgImage だけを見る
    /// - `Vision` の顔検出 … 向きを渡さないと横向きの顔を見つけられない
    /// - `jpegData()` 後の再読み込み … 経路によって orientation が落ちる
    ///
    /// フィルター処理の前に一度ここを通して向きを確定させてしまえば、
    /// 以降のパイプライン全体が同じ座標系で扱える。
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 横長の画像か
    var isLandscape: Bool { size.width > size.height }
}
