[English](../../README.md) | [日本語](README.md)

# Project TV - Rocky Linux Edition

Rocky Linux 10向けのKubernetesベースメディアサーバー。EPGStation、Mirakurun、Jellyfin、Tube Archivist、Navidromeを搭載。

本プロジェクトは[Project TV v2（Ubuntu版）](https://metalinux.dev/linux-journey/courses/project-tv-v2/)の後継であり、Docker ComposeをKubernetes（kubeadm）に置き換え、Rocky Linux向けにゼロから書き直されたものです。

## 帰属表示

以下のソフトウェアプロジェクトすべてに心から感謝します。これらなくして本スクリプトは実現できませんでした — ぜひ応援してください：

**オープンソース：**

- **[Rocky Linux](https://rockylinux.org/)** — 本プロジェクトを実現する基盤。素晴らしいコミュニティエンタープライズOS。**BSD-3-Clause**ライセンス。
- **[px4_drv](https://github.com/tsukumijima/px4_drv)** by [tsukumijima](https://github.com/tsukumijima)（原作：[nns779](https://github.com/nns779/px4_drv)）— PLEXおよびe-Better TVチューナー用Linuxドライバー。**GPL-2.0**ライセンス。これまでの全コントリビューターの方々によるドライバー開発に深く感謝します。この成果なくしてRPM版ドライバーの作成は実現できませんでした。
- **[EPGStation](https://github.com/l3tnun/EPGStation)** by [l3tnun](https://github.com/l3tnun) — デジタル放送録画システム。**MIT**ライセンス。
- **[Mirakurun](https://github.com/Chinachu/Mirakurun)** by [Chinachu](https://github.com/Chinachu) — デジタル放送チューナーサーバー。**Apache-2.0**ライセンス。
- **[Jellyfin](https://github.com/jellyfin/jellyfin)** — 最高のフリーソフトウェアメディアシステムの一つ。**GPL-2.0**ライセンス。
- **[Tube Archivist](https://github.com/tubearchivist/tubearchivist)** by [bbilly1](https://github.com/bbilly1) — YouTubeアーカイブマネージャー。**GPL-3.0**ライセンス。
- **[Navidrome](https://github.com/navidrome/navidrome)** — モダンな音楽サーバー＆ストリーマー。**GPL-3.0**ライセンス。
- **[Kubernetes](https://github.com/kubernetes/kubernetes)** — コンテナオーケストレーションプラットフォーム。**Apache-2.0**ライセンス。
- **[Prometheus](https://github.com/prometheus/prometheus)** — 時系列データベースを備えた監視・アラートシステム。**Apache-2.0**ライセンス。
- **[Grafana](https://github.com/grafana/grafana)** — オープンソースの可視化・監視プラットフォーム。**AGPL-3.0**ライセンス。
- **[Sanoid / Syncoid](https://github.com/jimsalterjrs/sanoid)** — ZFSスナップショット管理・レプリケーションツール。**GPL-3.0**ライセンス。
- **[KDE Plasma](https://github.com/KDE/plasma-desktop)** — 多機能デスクトップ環境。**GPL-2.0**ライセンス。
- **[Brave](https://brave.com/)** — プライバシー重視のウェブブラウザ。**MPL-2.0**ライセンス。
- **[Waterfox](https://www.waterfox.net/)** — プライバシー重視のFirefoxフォーク。**MPL-2.0**ライセンス。
- **[Firefox](https://www.mozilla.org/firefox/)** — Mozillaのオープンソースウェブブラウザ。**MPL-2.0**ライセンス。
- **[Chromium](https://www.chromium.org/)** — Chromeの基盤となるオープンソースブラウザプロジェクト。**BSD-3-Clause**ライセンス。

**プロプライエタリ：**

- **[MakeMKV](https://www.makemkv.com/)** — DVD・Blu-rayディスクリッパー。
- **[Google Chrome](https://www.google.com/chrome/)** — Googleのウェブブラウザ。
- **[Vivaldi](https://vivaldi.com/)** — 多機能ウェブブラウザ。
- **[Microsoft Edge](https://www.microsoft.com/edge)** — Microsoftのウェブブラウザ。

サードパーティソフトウェアは各自のライセンスを保持しています。本プロジェクトのインストーラースクリプトとKubernetesマニフェストは特に記載がない限りMITライセンスで提供されます。各アップストリームリポジトリのライセンス条件をご参照ください。

## AI利用方針

本リポジトリは[Fedora AI支援貢献ポリシー](https://docs.fedoraproject.org/en-US/council/policy/ai-contribution-policy/)に準拠しています。ClaudeのOpus 4.6モデルとClaude Codeを使用してすべてを作成し、開発プロセス全体を通じて人間によるテストとレビューを実施しています。

## 問題の報告

問題が発生した場合は、ぜひお知らせください！リポジトリの[Issue](https://github.com/metalllinux/project-tv-rocky-linux-edition/issues)に問題の説明を添えて報告してください。可能であれば、以下もご提供いただけると助かります：

- **インストーラーログファイル** — インストーラー実行後に`logs/`ディレクトリに保存されます
- **sosreport** — `sudo sos report`を実行してシステム診断レポートを生成してください。環境の把握に役立ちます

ご提供いただける情報が多いほど、問題の再現と修正が迅速に行えます。ご報告いただきありがとうございます！

## 概要

Project TV - Rocky Linux Editionは、Rocky Linux 10システムをKubernetes上で動作する本格的なメディアサーバーに変換します。対話型インストーラーが、ZFSストレージの設定からアプリケーションのデプロイまで、すべてのステップを案内します。

### アーキテクチャ

```
Rocky Linux 10（ホスト）
├── ZFSプール（ユーザー設定データセット）
├── Kubernetes（kubeadm + containerd + Flannel）
│   ├── Mirakurun（TVチューナー管理、ポート40772）
│   ├── EPGStation + MariaDB（TV録画/スケジューリング、ポート8888）
│   ├── Jellyfin（メディアサーバー、ポート8096）
│   ├── Tube Archivist + Redis + Elasticsearch（YouTubeアーカイブ、ポート8000）
│   ├── Navidrome（音楽サーバー、ポート4533）
│   ├── Prometheus + Node Exporter（モニタリング、ポート9090）
│   ├── Grafana（ダッシュボード、ポート3000）
│   └── CronJob: Jellyfinライブラリ更新（毎時）
├── Sanoid（ZFSスナップショット管理）
├── KDE Plasma（デスクトップ環境）
└── px4_drv（TVチューナーカーネルドライバー、DKMS RPM経由）
```

### Project TV v2からの主な改善点

- **Kubernetes**がDocker Composeに代わるコンテナオーケストレーション
- **Navidrome**による軽量なK8sネイティブ音楽サーバー
- **Jellyfin API CronJob**がvirt-manager VM方式のライブラリ更新を置き換え
- **動的ZFSデータセット** — インストーラーがデータセット名とマウントポイントを対話的に設定
- **px4_drv RPM** — 手動コンパイルではなくDKMS RPMパッケージ
- **Rocky Linux 10**をベースOSとし、Rocky 9および8でもテスト済み

## 前提条件

### ハードウェア要件

本プロジェクトは**x86_64**アーキテクチャ専用です。

- **CPU**: Rocky Linux 10がサポートするx86_64プロセッサ。Intel プロセッサは内蔵の**Intel Quick Sync Video（QSV）**ハードウェアエンコーディング機能により推奨されます。JellyfinのトランスコードやライブTVストリーミングのパフォーマンスが大幅に向上します。
  - **Intel（推奨）**: 第12世代 Alder Lake以降 — Core i3、i5、i7、i9、Pentium Gold、Intel UHD Graphics搭載Celeron
  - **AMD**: Ryzen 3000シリーズ以降 — 完全対応ですがソフトウェアエンコーディングのみ（Intel QSVなし）
- **RAM**: 最低16 GB（Elasticsearch単体で1 GB以上必要）
- **ストレージ**: OS＋アプリケーションデータ用に最低256 GB NVMe。ZFSメディアプール用に追加ディスク（HDDまたはSSD）を推奨。
- **ネットワーク**: ギガビットイーサネット

### TVチューナーハードウェア（オプション — 日本の放送向け）

ライブTV録画・ストリーミング機能は**日本のデジタル放送（ISDB-T / ISDB-S）**向けに設計されています。日本国外にお住まいの方やTV機能が不要な場合は、インストール時にモジュール06（px4_drv）と07（EPGStation + Mirakurun）をスキップできます — インストーラーは各モジュールの実行前に確認を求めます。

TV機能に必要なハードウェア：

| 部品 | 型番 | ID | 用途 |
|------|------|----|------|
| TVチューナー | PLEX PX-W3PE5 | USB `0511:073f` | 4チャンネルデジタルTVチューナー — 地上波（ISDB-T）×2 + 衛星（ISDB-S BS/CS）×2 |
| PCIe USBコントローラー | MosChip MCS9990 | PCIe | 8ポートPCIe-USB 2.0コントローラー — PX-W3PE5の接続に必要 |
| ICカードリーダー | SCM SCR331-LC1 / SCR3310 | USB `04e6:5116` | 日本の放送復号用B-CASカードの読み取り |
| B-CASカード | — | — | 日本の地上波・衛星放送の復号に必要（TVチューナーに同梱または別途購入） |

px4_drv対応の他のチューナー（PX-Q3PE5、PX-Q3U4、PX-MLT5PE等）も動作します — 必要に応じて`manifests/epgstation/mirakurun-configmap.yaml`のチューナー設定を変更してください。

### ソフトウェア要件

- Rocky Linux 10（最小構成またはKDEインストール）— 本インストーラーは既存のRocky Linux 10マシンでも動作します
- インターネット接続（パッケージとコンテナイメージのダウンロード用）
- sudo権限を持つユーザーアカウント

## クイックスタート

```bash
# リポジトリをクローン
git clone https://github.com/Metalllinux/project-tv-rocky-edition.git
cd project-tv-rocky-edition

# インストーラーを実行
sudo ./install.sh
```

インストーラーは対話型メインメニューを表示します：

```
Project TV - Rocky Linux Edition Installer
=====================================

  [1]  Full Installation (run all modules in order)
  [2]  Run a specific module
  [3]  View installation status
  [4]  View log file
  [5]  K8s health summary
  [q]  Quit
```

### メインメニューオプション

**[1] フルインストール** — すべてのモジュールを以下の実行順序で実行します。各モジュールの前に実行するかスキップするか確認されます。既に完了したモジュールは再実行するか確認されます。モジュールが失敗した場合、次のモジュールに進むか停止するかを選択できます。

**[2] 特定のモジュールを実行** — 全20モジュール（00〜12、14〜20）を番号順に表示します。モジュール番号を入力して個別に実行します。1桁の入力も可能です（`5`は`05`と同じ）。完了済みモジュールは`(done)`と表示されます。

**[3] インストール状況の表示** — 全モジュールの現在の状態を表示：`[OK]`完了、`[!!]`失敗、`[--]`スキップ、`[  ]`未実行。

**[4] ログファイルの表示** — 現在のセッションの直近30件のタイムスタンプ付きログエントリとエラー総数を表示します。

**[5] K8sヘルスサマリー** — Kubernetesクラスターの現在の状態を表示：ノードの状態、ポッドの正常性、サービスエンドポイント。Kubernetesインストール（モジュール03）後に利用可能です。

**[q] 終了** — インストーラーを終了します。終了時にログファイルのパスが表示されます。

## インストーラーログ

すべてのインストーラー出力は`logs/install-YYYYMMDD-HHMMSS.log`に記録されます。問題が発生した場合：

1. `[ERROR]`行を確認：`grep ERROR logs/install-*.log`
2. ログにはタイムスタンプ、実行コマンド、終了コードが含まれています
3. イシュー報告時は関連するログセクションを共有してください

## モジュール詳細

フルインストール時のモジュール実行順序。モジュール番号は固定（ファイル名に対応）ですが、実行順序は関連するタスクをグループ化しています：

**システムセットアップ:** 00 → 01 → 02 → 03 → 04 → 05 → 06

**デスクトップ・システム設定:** 17 → 16 → 15 → 18 → 14 → 12

**Kubernetesアプリケーションデプロイ:** 07 → 08 → 09 → 10 → 11

**追加機能・モニタリング:** 13 → 19 → 20

---

### モジュール00 — プリフライトチェック

インストール開始前にシステム要件を確認します：
- Rocky Linux 10であることを確認（9および8は警告付きで対応）
- CPUアーキテクチャ（x86_64必須）、RAM（16 GB推奨）、CPUコア数（4以上推奨）をチェック
- `dl.rockylinux.org`へのインターネット接続をテスト
- PX TVチューナーとICカードリーダーをUSB経由で検出
- ZFSプール作成用のブロックデバイスを一覧表示
- **不足パッケージの自動インストール** — `kernel-devel`、`kernel-modules-extra`、`git`、`gcc`、`podman`、`epel-release`等が不足している場合、自動インストールを提案

このモジュールにより、カスタムISOからインストールしたマシンだけでなく、**任意のRocky Linux 10マシン**でインストーラーが動作します。

### モジュール01 — タイムゾーン設定

- 現在のタイムゾーンを表示
- 確認または変更を促す（デフォルト：`Asia/Tokyo`）
- `/usr/share/zoneinfo/`にタイムゾーンが存在するか検証
- NTP同期を有効化

### モジュール02 — ZFSストレージ

メディアストレージ用のZFSプールとデータセットを作成します。ZFSが既にインストールされプールが存在する場合、検出して完了にスキップします。

**初回セットアップ時：**
1. OpenZFSリポジトリからDKMS経由でZFSをインストール
2. 利用可能なブロックデバイスとディスクIDを番号付きリストで表示
3. プール名（デフォルト：`mediapool`）、プールタイプ（mirror/single/raidz1/raidz2）、ディスク選択を番号入力で設定
4. 選択ディスク上の既存ファイルシステムを検出し、必要に応じて強制作成を提案
5. データセットの数、名前、マウントポイントを対話的に設定
6. 4Kセクターアライメントのため`ashift=12`でプールを作成
7. `config/datasets.conf`に設定を保存

### モジュール03 — Kubernetes（kubeadm）

フルアップストリームのKubernetesクラスターをインストールします。クラスターが既に稼働中でノードがReady状態の場合、現在の状態を表示して終了します。

**初回セットアップ時：**
1. SELinuxを設定（permissiveまたはenforcingを選択）
2. 必要なカーネルモジュールをすべてロード：`overlay`、`br_netfilter`、`nf_conntrack`、`xt_conntrack`、`xt_comment`、`xt_mark`、`ip_tables`、`ip6_tables`、`nf_nat`
3. Kubernetesネットワーク用のsysctlパラメータを設定
4. Docker CEリポジトリからcontainerdをインストール
5. Kubernetesリポジトリからkubeadm、kubelet、kubectlをインストール
6. swap を無効化（kubeadmの要件）
7. Flannel ポッドネットワークCIDRで`kubeadm init`を実行
8. Flannel CNIをインストールし、全システムポッド（Flannel、kube-proxy、CoreDNS）の起動を待機
9. シングルノード運用のためcontrol-planeテイントを除去

### モジュール04 — K8sネームスペース

全アプリケーションデプロイで使用する`project-tv`ネームスペースを作成します。

### モジュール05 — K8sストレージ（PV/PVC）

全アプリケーションのストレージパスを設定し、KubernetesのPersistentVolume/PersistentVolumeClaim マニフェストを生成します。

**各アプリケーションのデータ保存先を選択：**
- ZFSデータセットが存在する場合、番号付きリストで表示 — 番号を入力して選択
- NVMeや他のファイルシステム上の任意のパスも入力可能
- ZFSプールがない場合、NVMe上にディレクトリの作成を促す

**設定対象アプリケーション：**
| アプリケーション | 保存内容 | デフォルトパス |
|-----------------|---------|--------------|
| EPGStation | TV録画 | `/home/<ユーザー>/tv` |
| Jellyfin | メディアライブラリ（複数パス対応） | `/home/<ユーザー>/media` |
| Navidrome | 音楽コレクション | `/home/<ユーザー>/music` |
| Tube Archivist | YouTubeダウンロード | `/home/<ユーザー>/youtube` |
| MakeMKV | DVD/Blu-rayリッピング | `/home/<ユーザー>/rips` |
| Prometheus | メトリクスデータベース | `/var/lib/project-tv/prometheus/data` |
| Grafana | ダッシュボードデータ | `/var/lib/project-tv/grafana/data` |

ストレージパスは`config/storage-paths.conf`に保存され、後続の全モジュールから読み込まれます。

### モジュール06 — px4_drv TVチューナードライバー

PLEX TVチューナーデバイス（PX-W3PE5、PX-Q3PE5等）用のpx4_drv DKMSカーネルモジュールをインストールします：
1. ビルド前提パッケージとICカードリーダーサポート（pcsc-lite）をインストール
2. GitHubからpx4_drvソースをクローン
3. Rocky Linux 10カーネル6.12互換性のため`driver_module.c`にパッチ適用
4. DKMS経由でビルド・インストール（再実行時の既存DKMSエントリに対応）
5. ファームウェアとudevルールをインストール
6. モジュールをロードしデバイスノード（`/dev/px4video0-3`）を確認

### モジュール17 — ファイアウォールルール

全サービスのポートでfirewalldを設定します。firewalldが稼働していない場合、有効化を提案します。

**開放ポート：** Jellyfin（30096）、EPGStation（30888/30889）、Mirakurun（30772）、Tube Archivist（30800）、Navidrome（30453）、Kubernetes API（6443）、kubelet（10250）。

### モジュール16 — SDDM自動ログイン

SDDM（KDEディスプレイマネージャー）を設定し、起動時にインストーラーユーザーで自動ログインします。

### モジュール15 — ブラウザインストール

Flatpak経由でウェブブラウザをインストールします。複数選択メニュー：
- Google Chrome、Brave、Waterfox、Firefox、Vivaldi、Chromium、Microsoft Edge

インストール後、ブラウザが1つの場合は自動的にデフォルトに設定されます。複数の場合は番号付きリストから選択します。

### モジュール18 — デスクトップアプリケーション

オプションアプリケーションを個別にインストール（各アプリY/nで確認）：
- **SeaDrive** — Seafile仮想ドライブクライアント（AppImageとして`~/Applications/`にインストール）
- **MakeMKV** — DVD/Blu-rayリッパー（Flatpak経由）
- **Jellyfin Media Player** — デスクトップメディアクライアント（Flatpak経由）

### モジュール14 — KDEカスタマイズ

KDE Plasmaデスクトップを設定：
- スクリーンエッジを無効化（ホットコーナーなし）
- スリープ、サスペンド、画面調光を無効化
- **ibus-anthy**による日本語入力のインストールを提案

### モジュール12 — Sanoidスナップショット

Sanoid（ZFSスナップショットマネージャー）をGitHubからインストールし、自動スナップショットを設定：
- 保持数を設定：日次（デフォルト：60）、時間次（デフォルト：24）、週次（デフォルト：4）、月次（デフォルト：12）、年次（デフォルト：0）
- 時間次スナップショットが有効な場合、実行頻度を設定：毎時（デフォルト）、30分毎、15分毎、カスタム
- systemdタイマーとサービスユニットを作成

### モジュール07 — EPGStation + Mirakurun

日本のTV録画スタックをKubernetes上にデプロイ：
1. **カスタムコンテナイメージをビルド**（未作成の場合）：
   - recpt1搭載Mirakurun（px4_drv TVチューナーサポート用）
   - ffmpeg搭載EPGStation（ブラウザでのライブTVストリーミング用）
2. MariaDBのrootパスワードとEPGStationデータベースパスワードを入力
3. MariaDB、Mirakurun、EPGStationをConfigMap、Secret、Serviceと共にデプロイ
4. **TVチャンネルスキャン** — 地上波（GR）、BS衛星、CS衛星のスキャンを提案
5. スキャンしたチャンネルをサービスに反映するためMirakurunを再起動
6. チャンネルデータを取得するためEPGStationを再起動

**デプロイ後：**
- Mirakurun Web UI：`http://<ホストIP>:30772`
- EPGStation Web UI：`http://<ホストIP>:30888`
- ライブTV：EPGStationでチャンネルを選択し、HLS 720pまたは480p形式を選択

**利用可能なライブストリーミング形式：**
| 形式 | 説明 |
|------|------|
| M2TS | 生MPEG-TSパススルー（外部プレーヤーが必要） |
| M2TS-LL | 低遅延生MPEG-TS |
| HLS 720p / 480p | ブラウザネイティブストリーミング（推奨） |
| H.264 MP4 720p / 480p | ブラウザ向けフラグメントMP4 |
| WebM 720p / 480p | ブラウザ向けVP9ビデオ |

**チャンネルの再スキャン**（いつでも実行可能）：
```bash
# 地上波
curl -X PUT "http://<ホストIP>:30772/api/config/channels/scan?type=GR&setDisabledOnAdd=false"

# BS衛星
curl -X PUT "http://<ホストIP>:30772/api/config/channels/scan?type=BS&setDisabledOnAdd=false"

# CS衛星
curl -X PUT "http://<ホストIP>:30772/api/config/channels/scan?type=CS&setDisabledOnAdd=false"
```

### モジュール08 — Jellyfin

JellyfinメディアサーバーをKubernetes上にデプロイ：
- モジュール05で設定したメディアパスからボリュームマウントを動的に生成
- 各メディアディレクトリはコンテナ内の`/data/<ディレクトリ名>`に読み取り専用でマウント
- 既存デプロイを検出し、再実行時はスキップ

**デプロイ後：** `http://<ホストIP>:30096`

### モジュール09 — Tube Archivist

Tube Archivist（YouTubeアーカイブマネージャー）をRedisおよびElasticsearchと共にデプロイ：
- Tube Archivistのユーザー名/パスワードとElasticsearchパスワードを入力
- モジュール05で設定したダウンロードパスを使用
- 既存デプロイを検出し、再実行時はスキップ

**デプロイ後：** `http://<ホストIP>:30800`

### モジュール10 — Navidrome

Navidrome音楽サーバーをKubernetes上にデプロイ：
- モジュール05で設定した音楽パスを使用
- 既存デプロイを検出し、再実行時はスキップ

**デプロイ後：** `http://<ホストIP>:30453`

### モジュール11 — Jellyfinライブラリ更新

Jellyfin REST APIを定期的に呼び出してメディアライブラリを更新するKubernetes CronJobを作成：
1. JellyfinのURLを表示し、初期セットアップ（ユーザー作成、メディアライブラリ追加）を案内
2. APIキー生成を案内：設定 > 管理 > ダッシュボード > APIキー > 新しいAPIキー
3. cronスケジュールフォーマットを検証（5つのフィールドの視覚的な図を表示）
4. CronJobをデプロイ（デフォルト：毎時実行）

### モジュール13 — Rsyncメディア同期

ZFSデータセットのリモートサーバーへのrsyncベースバックアップを設定します。バックアップサーバー、SSHユーザー、リモートパスを入力します。

### モジュール19 — Prometheusモニタリング

メトリクス収集用のPrometheusをKubernetes上にデプロイ：
- RBAC（ServiceAccount、ClusterRole、ClusterRoleBinding）を設定
- モジュール05で設定したデータパスを使用
- データディレクトリに正しい所有権（UID 65534 / nobody）を設定

**デプロイ後：** `http://<ホストIP>:30090`

### モジュール20 — Grafanaダッシュボード

Prometheusをデフォルトデータソースとして設定済みのGrafanaをKubernetes上にデプロイ：
- Grafana管理者パスワードを入力
- モジュール05で設定したデータパスを使用
- データディレクトリに正しい所有権（UID 472 / grafana）を設定

**デプロイ後：** `http://<ホストIP>:30300`

## カスタムRocky Linux 10 ISOのビルド

すべての前提条件を含むRocky Linux 10を自動インストールし、初回起動時にKDE Plasmaと必須KDEアプリケーション（konsole、dolphin、kate、spectacle、ark、okular、gwenview、kcalc）をインストールするカスタムISOを作成できます。USBブート可能なISOとして、挿入してインストールを選択し、Project TVインストーラーの準備が整ったKDEで起動します。

詳細な手順は[英語版README](../../README.md#building-the-custom-rocky-linux-10-iso)を参照してください。

## 対応Rocky Linuxバージョン

| バージョン | 状態 | 備考 |
|-----------|------|------|
| Rocky Linux 10 | 主要対象 | 完全テスト済み・サポート |

## トラブルシューティング

### よくある問題

**ZFSモジュールのロード失敗**
- `kernel-devel`が実行中のカーネルと一致することを確認：`dnf install kernel-devel-$(uname -r)`
- DKMSモジュールをリビルド：`dkms autoinstall`

**KubernetesポッドがPendingのまま**
- PV/PVCバインディングを確認：`kubectl get pv,pvc -n project-tv`
- ZFSデータセットがマウントされていることを確認：`zfs list`

**MirakurunがTVチューナーを検出しない**
- px4_drvがロードされていることを確認：`lsmod | grep px4_drv`
- デバイスノードを確認：`ls -la /dev/px4video*`
- USBデバイスを確認：`lsusb | grep -i plex`
- ICカードリーダー用のpcscdを確認：`systemctl status pcscd`

**ElasticsearchのOOM**
- リソース制限を確認：`kubectl describe pod -n project-tv -l app=elasticsearch`
- 必要に応じてデプロイメントマニフェストでESヒープを削減

### ヘルプ

ここに記載されていない問題が発生した場合：
1. インストーラーログを確認：`grep ERROR logs/install-*.log`
2. 関連するログ出力を添えて本リポジトリにイシューを作成

## ライセンス

本リポジトリのインストーラースクリプトとKubernetesマニフェストは、特に記載がない限り[MITライセンス](../../LICENSE)で提供されます。

サードパーティソフトウェアは各自のライセンスを保持しています。本インストーラーがデプロイするソフトウェアのライセンス一覧：

| ソフトウェア | ライセンス |
|-------------|-----------|
| Rocky Linux | BSD-3-Clause |
| px4_drv | GPL-2.0 |
| EPGStation | MIT |
| Mirakurun | Apache-2.0 |
| Jellyfin | GPL-2.0 |
| Tube Archivist | GPL-3.0 |
| Navidrome | GPL-3.0 |
| Kubernetes | Apache-2.0 |
| Prometheus | Apache-2.0 |
| Grafana | AGPL-3.0 |
| Sanoid / Syncoid | GPL-3.0 |
| KDE Plasma | GPL-2.0 |
| Brave | MPL-2.0 |
| Waterfox | MPL-2.0 |
| Firefox | MPL-2.0 |
| Chromium | BSD-3-Clause |
| MakeMKV | プロプライエタリ |
| Google Chrome | プロプライエタリ |
| Vivaldi | プロプライエタリ |
| Microsoft Edge | プロプライエタリ |

完全なライセンス条項は各上流リポジトリを参照してください。
