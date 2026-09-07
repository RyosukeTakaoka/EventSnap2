//
//  HomeView.swift
//  EventSnap
//
//  ホーム画面
//

import SwiftUI

struct HomeView: View {
    // EventSnapAppが持つインスタンスをそのまま受け取る。以前は@StateObjectで
    // 独自インスタンスを作っていたため、`.environmentObject(eventViewModel)`で
    // 渡されるEventSnapApp側のインスタンス（Live Activity/Widgetのディープリンクで
    // `handleDeepLink`が`pendingTab`を更新する、実際にアプリの状態を持つ
    // インスタンス）とは別物になっていた。このアプリは`@EnvironmentObject`を
    // 一切使っていないため、そのenvironmentObject注入は実質どこにも読まれず、
    // ディープリンクの更新がUIへ一切届かないバグの原因になっていた。
    // 共有する形に変更する。
    @ObservedObject var eventViewModel: EventViewModel
    // MainTabViewを出すかどうかは、EventViewModel経由の間接的な状態ではなく
    // EventRepository.shared（真の情報源）から直接判定する。
    // 別インスタンスのEventViewModel同士が同期しきれない可能性を排除するため。
    @ObservedObject private var eventRepository = EventRepository.shared

    /// いま出しているシート。
    ///
    /// 以前は `showEventCreation` / `showQRScanner` の2つの `.sheet` を
    /// 同じビューに重ねていた。SwiftUIは1つのビューから同時に1枚しか
    /// シートを出せないため、この形は「片方が閉じきる前にもう片方を出そうとすると
    /// 黙って無視される」という壊れ方をする。1つの状態に束ねて、
    /// 同時に2枚出そうとする状態自体を作れないようにする。
    @State private var activeSheet: HomeSheet?
    @State private var eventName = ""

    /// シートが閉じきったあとに作成するイベント名。`nil` なら作成待ちは無い。
    @State private var pendingEventName: String?

    /// 参加中のイベントがあるか（＝MainTabViewを出すべきか）。
    /// `EventRepository.currentEvent` を写したもの。
    @State private var hasEvent = false

    /// 実際にMainTabViewを提示しているか。
    ///
    /// `hasEvent` と分けているのは、**シートが出ている（閉じている途中も含む）間は
    /// 提示してはいけない**ため。詳しくは `presentEventIfPossible()` を参照。
    @State private var isEventOpen = false

    /// ホーム画面から出すシート。
    private enum HomeSheet: String, Identifiable {
        case eventCreation
        case qrScanner

        var id: String { rawValue }
    }

    var body: some View {
#if DEBUG
        // ⑥ 招待+読み取りの合成カットは、通常のHomeView→MainTabViewの導線とは
        // 別物（QRコードとスキャン画面を重ねた専用View）なので、このシーンの
        // ときだけ丸ごと差し替える。それ以外のシーン・通常起動では影響しない。
        //
        // `QROverlayScreenshotView`はファイルごと`#if DEBUG`で囲われている
        // （Preview/QROverlayScreenshotView.swift）ため、この分岐も`#if DEBUG`の
        // 中に置く必要がある。以前は分岐だけが無条件に書かれていたため、
        // **ReleaseビルドではHomeViewがコンパイルできなかった**
        // （"Cannot find 'QROverlayScreenshotView' in scope"）。
        if ScreenshotMode.isActive && ScreenshotMode.scene == .inviteOverlay {
            QROverlayScreenshotView()
        } else {
            mainContent
        }
#else
        mainContent
#endif
    }

    /// 通常のホーム画面。
    private var mainContent: some View {
        NavigationView {
            ZStack {
                // 背景は白（ごく薄いDesignTokens.primaryのティント）。
                // 一時期DesignTokens.primaryの単色ベタ塗りにしていたが、
                // 「新しいイベントを作成」ボタンやQRファインダー枠のような
                // ブランドカラーの要素が背景に溶けて見づらくなったため、
                // 白背景の上にそれらの要素だけ単色で乗せる形に戻す。
                DesignTokens.primary.opacity(0.06)
                    .ignoresSafeArea()

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 32) {
                            Spacer(minLength: 24)

                            titleSection

                            qrFinderSection

                            actionsSection

                            // イベント終了は「そのイベントだけ」に効く操作。
                            // タイトル画面に戻っても、他に参加しているイベントには
                            // すぐ入れるよう一覧を出しておく。
                            if !eventViewModel.recentEvents.isEmpty {
                                joinedEventsSection
                            }

                            Spacer(minLength: 24)
                        }
                        .frame(minHeight: proxy.size.height)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
                switch sheet {
                case .eventCreation:
                    // ここでは作成しない。入力されたイベント名を控えるだけにして、
                    // 実際の作成はシートが閉じきってから `handleSheetDismiss` が行う。
                    EventCreationSheet(eventName: $eventName) { name in
                        pendingEventName = name
                    }
                case .qrScanner:
                    QRScannerView(eventViewModel: eventViewModel)
                }
            }
            .fullScreenCover(isPresented: $isEventOpen) {
                // 作成直後は招待画面、参加直後はアルバム。
                // どちらに飛ばすかは EventViewModel.pendingTab が決める。
                // 撮影モードのときだけ、撮りたいシーンのタブを優先する
                // （通常起動・Releaseでは `initialTab` は常に nil）。
                //
                // MainTabViewには必ずこの画面と同じeventViewModelインスタンスを渡す。
                // 別インスタンスを渡すと、アプリ起動中にLive Activity/Widgetから
                // ディープリンクを受けてもMainTabView側のpendingTabが更新されず、
                // タブが切り替わらなくなる。
                MainTabView(
                    eventViewModel: eventViewModel,
                    initialTab: ScreenshotMode.initialTab ?? eventViewModel.pendingTab ?? .album
                )
            }
            // 失敗の理由を必ず画面に出す。以前は print だけだったので、
            // iCloud未サインインで作成に失敗しても何も起きないように見えていた。
            .alert("うまくいきませんでした",
                   isPresented: Binding(get: { eventViewModel.error != nil },
                                        set: { if !$0 { eventViewModel.error = nil } })) {
                Button("OK", role: .cancel) { eventViewModel.error = nil }
            } message: {
                Text(eventViewModel.error ?? "")
            }
            .overlay {
                if eventViewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                    }
                }
            }
        }
        // iPadでは NavigationView が既定で2カラムの分割表示になり、中身が
        // サイドバー側へ押し込まれて見えなくなる（横向きでは細い左カラム、
        // 縦向きでは何も出ない）。iPhoneと同じ1画面のスタック表示に固定する。
        // アプリ内の他の NavigationView にも同じ理由で付けている。
        .navigationViewStyle(.stack)
        .onChange(of: eventRepository.currentEvent) { _, event in
            hasEvent = event != nil
            presentEventIfPossible()
        }
        .task {
            hasEvent = eventRepository.currentEvent != nil
            presentEventIfPossible()
            await eventViewModel.loadRecentEvents()
        }
    }

    // MARK: - イベント作成／参加の後始末

    /// シートが完全に閉じたあとに呼ばれる。
    ///
    /// ## なぜ作成をここまで遅らせるのか
    ///
    /// 以前は「作成する」を押した瞬間に作成処理を走らせ、同時にシートを
    /// 閉じていた。作成が終わると `EventRepository.currentEvent` が入り、
    /// この画面の `fullScreenCover` が開く…はずだが、**シートが閉じる
    /// アニメーションの最中に提示しようとすると、その提示はUIKitに
    /// 丸ごと捨てられる**（"while a presentation is in progress"）。
    ///
    /// さらに `fullScreenCover` のbindingは `currentEvent != nil` から
    /// 計算していて、setterが空だった。一度「提示済み」と見なされると
    /// 状態が変化しないため、SwiftUIは二度と提示をやり直さない。
    /// 結果として **イベントはCloudKitに作られているのに画面はホームのまま**
    /// ＝「イベントが作成できない」という見え方になる。
    ///
    /// CloudKitへの保存がシートの開閉アニメーション（約0.35秒）より速く
    /// 終わったときにだけ起きるので、回線の速い環境でのみ再現する
    /// （手元の端末では再現せず、審査でだけ起きる）という形になっていた。
    private func handleSheetDismiss() {
        // 閉じている間に確定したイベント（QRコードで参加した場合）があれば、
        // ここで初めて提示する。
        presentEventIfPossible()

        guard let name = pendingEventName else { return }
        pendingEventName = nil
        Task { await eventViewModel.createEvent(name: name) }
    }

    /// シートが出ていないときに限り、MainTabViewを提示する。
    ///
    /// シートが出ている間は提示せず、`handleSheetDismiss` まで持ち越す。
    private func presentEventIfPossible() {
        guard activeSheet == nil else { return }
        if isEventOpen != hasEvent {
            isEventOpen = hasEvent
        }
    }

    // MARK: - アプリタイトル

    private var titleSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(DesignTokens.primary)

            Text("EventSnap")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(DesignTokens.primary)

            Text("思い出を、みんなで")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - QRファインダー

    /// カメラファインダー風の大きな四角。QRコードで参加する導線を視覚的に
    /// 目立たせるための装飾で、タップ時の処理は`actionsSection`のQRスキャン
    /// ボタンと同じ`activeSheet = .qrScanner`を設定するだけ（QRScannerView自体は
    /// 一切変更しない）。既存のボタン・遷移ロジックはそのまま残す。
    ///
    /// 背景が白に戻ったため、枠自体をDesignTokens.primaryの濃い単色で塗り、
    /// 白背景に対してくっきり見えるコントラストを確保する
    /// （以前は白背景ベタ塗りに対して白い枠線を重ねる配色だったため、逆転させている）。
    private var qrFinderSection: some View {
        Button {
            activeSheet = .qrScanner
        } label: {
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusLarge, style: .continuous)
                .fill(DesignTokens.primary)
                .frame(width: 180, height: 180)
                .overlay {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(.white)
                }
                .shadow(color: DesignTokens.primary.opacity(0.3), radius: 10, y: 4)
        }
        .accessibilityLabel("QRコードで参加")
    }

    // MARK: - メインアクション

    private var actionsSection: some View {
        VStack(spacing: 20) {
            // イベント作成ボタン。白背景の上でくっきり見えるよう、
            // 共通のPrimaryButtonStyle（白背景+青文字。薄い背景の画面向け）ではなく、
            // DesignTokens.primaryの濃い単色塗りにする。
            Button {
                activeSheet = .eventCreation
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("新しいイベントを作成")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(DesignTokens.primary)
                .foregroundColor(.white)
                .cornerRadius(16)
            }

            // QRスキャンボタン（アウトライン、primaryカラー）
            Button {
                activeSheet = .qrScanner
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text("QRコードで参加")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(DesignTokens.primary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DesignTokens.primary, lineWidth: 2)
                )
            }

            // 参加経路はQRコードだけ。その場に居合わせた人しか
            // 入れないことがEventSnapの前提なので、コードを
            // 伝えるだけで参加できる手段は用意しない。
            Text("参加できるのはQRコードを読み取った人だけです")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - 参加中のイベント

    /// 作成・参加したことのあるイベントへすぐ戻れる一覧。
    /// 終了済みのイベントもここから開ける（新しい写真は追加できない）。
    ///
    /// 「現在」と「過去」を分けて表示する。以前は「参加中のイベント」という
    /// 見出しの下に終了済みイベントまで並んでいて、見出しと中身が矛盾していた。
    private var joinedEventsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            let current = eventViewModel.recentEvents.filter(\.isActive)
            let past = eventViewModel.recentEvents.filter { !$0.isActive }

            if !current.isEmpty {
                eventGroup(title: "現在", events: current)
            }

            if !past.isEmpty {
                eventGroup(title: "過去のイベント", events: past)
            }
        }
        .padding(.horizontal, 40)
    }

    private func eventGroup(title: String, events: [Event]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(events) { event in
                    Button {
                        Task { await eventViewModel.switchEvent(to: event) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.name)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Text("\(event.participantIDs.count)人")
                                    if !event.isActive {
                                        Text("終了")
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.18))
                                            .cornerRadius(4)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                    }
                }
            }
        }
    }
}

// MARK: - イベント作成シート

struct EventCreationSheet: View {
    @Binding var eventName: String
    @Environment(\.dismiss) var dismiss

    /// 入力されたイベント名を呼び出し側へ渡すだけのコールバック。
    ///
    /// **このシートの中でイベントを作ってはいけない**。作成が終わると
    /// 呼び出し側が全画面のMainTabViewを出すが、シートが閉じる途中に
    /// 提示しようとするとその提示は捨てられてしまう（HomeViewの
    /// `handleSheetDismiss` のコメントを参照）。
    let onCreate: (String) -> Void

    /// 表示名の入力欄。まだ本人が決めたことが無いときだけ出す
    /// （`DeviceIdentity.hasCustomDisplayName`）。一度決めれば、以後の
    /// 作成・参加では出さない。変更したくなったら設定タブから直せる。
    @State private var displayName = DeviceIdentity.displayName
    private let needsDisplayName = !DeviceIdentity.hasCustomDisplayName

    var body: some View {
        NavigationView {
            ZStack {
                // HomeViewのブランドカラーを、ここでは主張しすぎない濃度で
                // 引き継ぐ。真っ白なシートが唐突に被さる違和感を無くすため。
                // DesignTokens統一に合わせ、二色グラデーションから単色ベースに変更。
                DesignTokens.primary.opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("イベントを作成")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("イベント名を入力してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)

                    TextField("例: 文化祭2024", text: $eventName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    // 初めてイベントを作る人には、ここで表示名も一緒に決めてもらう。
                    // タイムカプセルの通知（「〇〇さんの新しい思い出」）や参加者一覧に使われる。
                    if needsDisplayName {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("あなたの表示名")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("例: たかし", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal)
                    }

                    Button("作成する") {
                        if needsDisplayName {
                            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmedName.isEmpty {
                                DeviceIdentity.setDisplayName(trimmedName)
                            }
                        }

                        // 空白だけの入力も「未入力」として扱う
                        let trimmed = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(trimmed.isEmpty ? "新しいイベント" : trimmed)
                        dismiss()
                    }
                    .buttonStyle(.primary)
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationBarItems(trailing: Button("キャンセル") {
                dismiss()
            })
        }
        // iPadでシートが分割表示になると、イベント名の入力欄と「作成する」が
        // 隠れたサイドバー側に押し込まれ、「キャンセル」しか押せなくなる。
        // ＝iPadでだけイベントを作れない状態になるため、スタック表示に固定する。
        .navigationViewStyle(.stack)
    }
}

#Preview {
    HomeView(eventViewModel: EventViewModel())
}
