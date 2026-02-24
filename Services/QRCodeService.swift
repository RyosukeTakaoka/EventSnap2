//
//  QRCodeService.swift
//  EventSnap
//
//  QRコード生成・読み取りサービス（非同期デバッグ版）
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

class QRCodeService {

    /// QRコードを非同期で生成（デバッグ版）
    /// - Parameters:
    ///   - eventID: イベントID
    ///   - completion: 生成完了時のコールバック（メインスレッドで実行される）
    static func generateQRCode(from eventID: String, completion: @escaping (UIImage?) -> Void) {
        let totalStartTime = Date()
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🚀 QRコード生成開始（非同期処理）")
        print("📝 イベントID: \(eventID)")
        print("📏 イベントIDの長さ: \(eventID.count)文字")
        print("🧵 現在のスレッド: \(Thread.current.isMainThread ? "メインスレッド⚠️" : "バックグラウンドスレッド✅")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // バックグラウンドスレッドで実行（重要！）
        DispatchQueue.global(qos: .userInitiated).async {
            print("\n🔄 バックグラウンドスレッドに切り替えました")
            print("🧵 処理スレッド: \(Thread.current.isMainThread ? "メインスレッド⚠️" : "バックグラウンドスレッド✅")")
            
            // ステップ1: データ変換
            let step1Start = Date()
            print("\n【ステップ1】データ変換開始...")
            
            guard let data = eventID.data(using: .utf8) else {
                print("❌ エラー: データ変換に失敗しました")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let step1Time = Date().timeIntervalSince(step1Start)
            print("✅ データ変換成功")
            print("📦 データサイズ: \(data.count)バイト")
            print("⏱ ステップ1の処理時間: \(String(format: "%.4f", step1Time))秒")
            
            // ステップ2: CIContext作成
            let step2Start = Date()
            print("\n【ステップ2】CIContext作成開始...")
            
            let context = CIContext()
            
            let step2Time = Date().timeIntervalSince(step2Start)
            print("✅ CIContext作成成功")
            print("⏱ ステップ2の処理時間: \(String(format: "%.4f", step2Time))秒")
            
            // ステップ3: QRコードフィルター作成・設定
            let step3Start = Date()
            print("\n【ステップ3】QRコードフィルター設定開始...")
            
            let filter = CIFilter.qrCodeGenerator()
            print("  - フィルター作成完了")
            
            filter.message = data
            print("  - メッセージ設定完了")
            
            filter.correctionLevel = "H" // 高エラー訂正
            print("  - エラー訂正レベル設定: H（高）")
            
            let step3Time = Date().timeIntervalSince(step3Start)
            print("✅ フィルター設定成功")
            print("⏱ ステップ3の処理時間: \(String(format: "%.4f", step3Time))秒")
            
            // ステップ4: CIImage生成
            let step4Start = Date()
            print("\n【ステップ4】CIImage生成開始...")
            
            guard let ciImage = filter.outputImage else {
                print("❌ エラー: CIImageの生成に失敗しました")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let step4Time = Date().timeIntervalSince(step4Start)
            print("✅ CIImage生成成功")
            print("📐 元のCIImageサイズ: \(ciImage.extent.size)")
            print("⏱ ステップ4の処理時間: \(String(format: "%.4f", step4Time))秒")
            
            // ステップ5: 画像の拡大変換
            let step5Start = Date()
            print("\n【ステップ5】画像拡大処理開始...")
            print("  - 拡大率: 10倍")
            
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = ciImage.transformed(by: transform)
            
            let step5Time = Date().timeIntervalSince(step5Start)
            print("✅ 画像拡大成功")
            print("📐 拡大後のサイズ: \(scaledImage.extent.size)")
            print("⏱ ステップ5の処理時間: \(String(format: "%.4f", step5Time))秒")
            
            // ステップ6: CGImage作成（ここが一番重い処理）
            let step6Start = Date()
            print("\n【ステップ6】CGImage作成開始...")
            print("  ⚠️ この処理は時間がかかる可能性があります...")
            
            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                print("❌ エラー: CGImageの生成に失敗しました")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let step6Time = Date().timeIntervalSince(step6Start)
            print("✅ CGImage生成成功")
            print("📐 CGImageサイズ: \(cgImage.width) x \(cgImage.height)")
            print("🎨 カラースペース: \(cgImage.colorSpace?.name as String? ?? "不明")")
            print("⏱ ステップ6の処理時間: \(String(format: "%.4f", step6Time))秒")
            
            if step6Time > 0.1 {
                print("  ⚠️ 警告: CGImage生成に0.1秒以上かかっています！")
            }
            
            // ステップ7: UIImage作成
            let step7Start = Date()
            print("\n【ステップ7】UIImage作成開始...")
            
            let finalImage = UIImage(cgImage: cgImage)
            
            let step7Time = Date().timeIntervalSince(step7Start)
            print("✅ UIImage作成成功")
            print("📐 最終的な画像サイズ: \(finalImage.size)")
            print("🔍 画像スケール: \(finalImage.scale)")
            print("⏱ ステップ7の処理時間: \(String(format: "%.4f", step7Time))秒")
            
            // 全体のまとめ
            let totalTime = Date().timeIntervalSince(totalStartTime)
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🎉 QRコード生成完了！")
            print("\n【処理時間の内訳】")
            print("  ステップ1（データ変換）    : \(String(format: "%.4f", step1Time))秒 (\(String(format: "%.1f", step1Time/totalTime*100))%)")
            print("  ステップ2（Context作成）   : \(String(format: "%.4f", step2Time))秒 (\(String(format: "%.1f", step2Time/totalTime*100))%)")
            print("  ステップ3（フィルター設定） : \(String(format: "%.4f", step3Time))秒 (\(String(format: "%.1f", step3Time/totalTime*100))%)")
            print("  ステップ4（CIImage生成）   : \(String(format: "%.4f", step4Time))秒 (\(String(format: "%.1f", step4Time/totalTime*100))%)")
            print("  ステップ5（画像拡大）       : \(String(format: "%.4f", step5Time))秒 (\(String(format: "%.1f", step5Time/totalTime*100))%)")
            print("  ステップ6（CGImage生成）   : \(String(format: "%.4f", step6Time))秒 (\(String(format: "%.1f", step6Time/totalTime*100))%)")
            print("  ステップ7（UIImage作成）   : \(String(format: "%.4f", step7Time))秒 (\(String(format: "%.1f", step7Time/totalTime*100))%)")
            print("  ─────────────────────────────────")
            print("  合計                      : \(String(format: "%.4f", totalTime))秒")
            
            // パフォーマンス評価
            print("\n【パフォーマンス評価】")
            if totalTime < 0.1 {
                print("  🟢 優秀: 非常に高速です")
            } else if totalTime < 0.5 {
                print("  🟡 普通: 許容範囲内です")
            } else if totalTime < 1.0 {
                print("  🟠 やや遅い: 最適化の余地があります")
            } else {
                print("  🔴 遅い: 最適化が必要です")
            }
            
            // 最も時間がかかった処理を特定
            let steps = [
                ("データ変換", step1Time),
                ("Context作成", step2Time),
                ("フィルター設定", step3Time),
                ("CIImage生成", step4Time),
                ("画像拡大", step5Time),
                ("CGImage生成", step6Time),
                ("UIImage作成", step7Time)
            ]
            
            if let slowestStep = steps.max(by: { $0.1 < $1.1 }) {
                print("  🐌 最も時間がかかった処理: \(slowestStep.0) (\(String(format: "%.4f", slowestStep.1))秒)")
            }
            
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
            
            // メインスレッドで結果を返す
            DispatchQueue.main.async {
                print("🔄 メインスレッドに戻りました")
                completion(finalImage)
            }
        }
    }

    /// QRコードにロゴを重ねる(オプション)（非同期デバッグ版）
    /// - Parameters:
    ///   - qrImage: QRコード画像
    ///   - logo: 中央に配置するロゴ画像
    ///   - completion: 完了時のコールバック
    static func addLogo(to qrImage: UIImage, logo: UIImage, completion: @escaping (UIImage?) -> Void) {
        let totalStartTime = Date()
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎨 ロゴ追加処理開始（非同期処理）")
        print("📐 QRコードサイズ: \(qrImage.size)")
        print("📐 ロゴサイズ: \(logo.size)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let size = qrImage.size
            
            // グラフィックスコンテキスト作成
            let step1Start = Date()
            print("\n【ステップ1】グラフィックスコンテキスト作成...")
            
            UIGraphicsBeginImageContextWithOptions(size, false, qrImage.scale)
            
            let step1Time = Date().timeIntervalSince(step1Start)
            print("✅ コンテキスト作成完了")
            print("⏱ 処理時間: \(String(format: "%.4f", step1Time))秒")
            
            defer {
                UIGraphicsEndImageContext()
                print("🧹 コンテキストをクリーンアップしました")
            }

            // QRコードを描画
            let step2Start = Date()
            print("\n【ステップ2】QRコード描画...")
            
            qrImage.draw(in: CGRect(origin: .zero, size: size))
            
            let step2Time = Date().timeIntervalSince(step2Start)
            print("✅ QRコード描画完了")
            print("⏱ 処理時間: \(String(format: "%.4f", step2Time))秒")

            // ロゴサイズ計算
            let step3Start = Date()
            print("\n【ステップ3】ロゴ配置計算...")
            
            let logoSize = CGSize(width: size.width * 0.2, height: size.height * 0.2)
            let logoOrigin = CGPoint(
                x: (size.width - logoSize.width) / 2,
                y: (size.height - logoSize.height) / 2
            )
            
            let step3Time = Date().timeIntervalSince(step3Start)
            print("✅ ロゴ配置計算完了")
            print("📐 ロゴサイズ(20%): \(logoSize)")
            print("📍 ロゴ位置: \(logoOrigin)")
            print("⏱ 処理時間: \(String(format: "%.4f", step3Time))秒")
            
            // ロゴを描画
            let step4Start = Date()
            print("\n【ステップ4】ロゴ描画...")
            
            logo.draw(in: CGRect(origin: logoOrigin, size: logoSize))
            
            let step4Time = Date().timeIntervalSince(step4Start)
            print("✅ ロゴ描画完了")
            print("⏱ 処理時間: \(String(format: "%.4f", step4Time))秒")
            
            // 最終画像取得
            let step5Start = Date()
            print("\n【ステップ5】最終画像取得...")
            
            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            
            let step5Time = Date().timeIntervalSince(step5Start)
            
            if let image = finalImage {
                print("✅ 最終画像取得成功")
                print("📐 最終画像サイズ: \(image.size)")
            } else {
                print("❌ エラー: 最終画像の取得に失敗しました")
            }
            print("⏱ 処理時間: \(String(format: "%.4f", step5Time))秒")
            
            // 全体のまとめ
            let totalTime = Date().timeIntervalSince(totalStartTime)
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🎉 ロゴ追加処理完了！")
            print("\n【処理時間の内訳】")
            print("  コンテキスト作成: \(String(format: "%.4f", step1Time))秒")
            print("  QRコード描画    : \(String(format: "%.4f", step2Time))秒")
            print("  ロゴ配置計算    : \(String(format: "%.4f", step3Time))秒")
            print("  ロゴ描画        : \(String(format: "%.4f", step4Time))秒")
            print("  最終画像取得    : \(String(format: "%.4f", step5Time))秒")
            print("  ─────────────────────")
            print("  合計           : \(String(format: "%.4f", totalTime))秒")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

            DispatchQueue.main.async {
                completion(finalImage)
            }
        }
    }
}
