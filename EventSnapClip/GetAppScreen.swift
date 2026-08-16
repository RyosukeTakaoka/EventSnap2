//
//  GetAppScreen.swift
//  EventSnapClip
//
//  「投稿するにはアプリが必要です」の案内画面。
//
//  App Clipから写真を投稿させない、という製品判断の核心部分。
//  ここでApp Store誘導のSKOverlayを表示する。App Clipと同じApp Store
//  Connectレコードに紐づくフルアプリを自動的に案内してくれるため、
//  App Store IDをコードに埋め込む必要がない（未公開の段階でも実装できる）。
//

import SwiftUI
import StoreKit

struct GetAppScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundColor(.blue)

                VStack(spacing: 10) {
                    Text("続きはアプリで")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("この写真をイベントの参加者と共有するには、\nEventSnapアプリが必要です。\n無料でダウンロードできます。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
            .navigationBarItems(trailing: Button("閉じる") { dismiss() })
        }
        .background(AppStoreOverlayPresenter())
    }
}

/// SKOverlayを表示するための橋渡し。
/// SwiftUIには直接のAPIが無いため、透明なUIViewControllerを介して
/// 現在のWindowSceneを取得し、標準の「Get」バナーを表示する。
private struct AppStoreOverlayPresenter: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let scene = uiViewController.view.window?.windowScene else { return }
        let config = SKOverlay.AppClipConfiguration(position: .bottom)
        SKOverlay(configuration: config).present(in: scene)
    }
}
