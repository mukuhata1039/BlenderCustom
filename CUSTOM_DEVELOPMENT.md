# BlenderCustom 開発引き継ぎ書

## このファイルの目的
このリポジトリは、Blender 本体の独自改造と自作アドオンをまとめて管理するためのもの。
別の ChatGPT 会話でも、このファイルとリポジトリを確認すれば開発を再開できるようにする。

## リポジトリと開発環境
- GitHub: https://github.com/mukuhata1039/BlenderCustom
- ローカル作業ディレクトリ: `D:\BlenderCustom`
- 自分の Git リモート: `origin` → `https://github.com/mukuhata1039/BlenderCustom.git`
- Blender 公式 Git リモート: `upstream` → `https://projects.blender.org/blender/blender.git`
- 主要ブランチ: `main`
- Windows / PowerShell を使用
- 現在使用中の通常版 Blender は保持し、独自ビルドは別環境に置く

## 開発の基本運用（最重要）
1. **アシスタントが GitHub のリポジトリを直接確認し、ソースコードを変更・コミットする。**
2. **ユーザーはローカルで以下を実行して、完成済みの変更を取得するだけ。**
   ```powershell
   git -C "D:\BlenderCustom" pull --ff-only origin main
   ```
3. GitHub での編集をユーザーに代行させたり、ローカルで `git add` / `git commit` / `git push` を実行させたりするのを標準手順にしない。
4. GitHub Desktop は使用しない。
5. GitHub の更新前に、実コード・既存機能・影響範囲を確認し、変更点をユーザーに説明する。
6. ユーザーが実装を指示する前に勝手に機能追加や書き換えを始めない。実装指示があれば、可能な限り GitHub を直接編集する。
7. 必要な操作は小分けの逐次確認を避け、PowerShell コマンドと手順をまとめて伝える。
8. ユーザーがローカルで実行するのは Pull・ビルド・テストなどのローカルでしか行えない作業が基本。
9. GitHub への直接操作が不可能な場合だけ、その理由を明示し、代替手段を相談する。

## 開発状況（2026-10-28時点）
- Blender 公式 GitHub ミラーから、自分の `BlenderCustom` リポジトリをフォーク済み。
- `D:\BlenderCustom` に `main` ブランチをクローン済み。
- `origin` と `upstream` を登録済み。
- クローン時の `git status` は clean。
- 改造版 Blender のビルド環境は **まだ整備していない**。
- Blender 本体の独自改造は **まだ開始していない**。
- 既存の通常版 Blender はそのまま使用中。

## DesignDoll → Blender アニメーション画像出力
- DesignDoll でポーズの異なる複数ドールを作成し、まとめて OBJ 形式でエクスポート。
- Blender ではドールごとに独立したオブジェクトとして読み込める。
- 1つの `.blend` に複数のアニメーション用コレクションを追加して管理したい。
- アニメーションごとに独立したカメラを配置する。
- 各コレクションに `model1`, `model2`, … を入れ、名前の数字順に出力。
- Blender の自動命名サフィックス（例: `model1.001`）にも対応する方針。
- 背景透過 PNG / カメラ固定 / コレクション単位の出力。
- 「DesignDoll Animation Exporter」アドオンを作成・インストールし、ユーザーが実際に出力成功を確認済み。
- **このアドオンのソースは、このリポジトリにはまだ取り込んでいない。** インストール済み Blender 側のアドオン保存フォルダから回収するなどの対応が必要。
- 自作アドオンを最終的にはこのリポジトリに管理し、独自 Blender に同梱したい。

## 次の候補作業
1. 公式 Windows ビルド手順に沿って、必要なコンパイラ・ツールと依存ライブラリを確認する。
2. 独自 Blender を通常版とは別にビルド・起動できるようにする。
3. インストール済みの自作アドオンを回収し、リポジトリで管理する。
4. Blender 公式の更新を取り込む手順を、安全に運用できるようにする。

## 注意事項
- ユーザーのローカルディレクトリ内のファイルを、GitHub 側の操作だけで直接変更することはできない。更新後にユーザーが Pull を実行する。
- `git pull --ff-only` がローカル変更や競合で失敗したら、ユーザーの変更を勝手に破棄せず、状態を確認して対処する。
- Blender 公式リポジトリのアップデートは、`upstream` を登録しただけでは自動では反映されない。
- 本体ビルドやアドオン動作を、実際に検証するまでは「検証済み」と表現しない。

## ビルド手順（2026-10-28 追加・実機ビルドは未検証）
- VS2022 Build Tools、MSVC、Windows SDK、Visual Studio付属CMakeの存在確認が完了。
- 準備確認スクリプト：`custom_tools/prepare_build_environment.ps1`。
- 依存ライブラリ取得と独立ビルド：`custom_tools/build_blender.ps1`。
- ユーザーは、アシスタントがGitHubに反映した後、次をPowerShellで実行する。
  ```powershell
  git -C "D:\BlenderCustom" pull --ff-only origin main
  powershell -NoProfile -ExecutionPolicy Bypass -File "D:\BlenderCustom\custom_tools\build_blender.ps1"
  ```
- ライブラリだけ取得するときは、同じスクリプトに `-LibrariesOnly` を追加。
- `make update` はソース側の `upstream/main` を更新する可能性があるため、このスクリプトは使わず、Gitのサブモジュールから固定バージョンのWindows依存ライブラリを取得する。
- 本体のLFSは公式upstreamから取得し、既存ソースコードの編集・削除はしない。
- ビルド先は通常 `D:\build_windows_x64_vc17_Release\bin\Release\blender.exe`。現在の通常版Blenderは上書きしない。
- スクリプトをGitHubに追加しただけではビルド成功は未確認。ユーザーの実行結果を受けて対処する。

## 初回ビルド時の Visual Studio 2022 バージョン問題（2026-10-28）
- Windows の依存ライブラリ LFS（約7GB）の取得は正常完了。
- 最初の CMake 実行で `CMAKE_CXX_COMPILER_VERSION=19.44.35214` を検出し、Blender 要件 `19.44.35216`（VS2022 17.14.14）未満で停止した。
- Visual Studio Developer Command Prompt は `17.14.12`。一方 `vswhere -property installationVersion` は `17.14.36408.4` であり、この番号を `17.14.14` と比較した従来の環境判定は誤り。
- `prepare_build_environment.ps1` と `build_blender.ps1` は、`vswhere -format json` の `catalog.productDisplayVersion` を比較するよう修正済み。
- Microsoft公式の Visual Studio Installer 更新手順を `custom_tools/update_vs2022.ps1` に実装。管理者許可が必要。
- 更新後は `custom_tools/build_blender.ps1` を再実行する。取得済みLFSライブラリはローカルに残り、全件ダウンロードし直す必要はない。
- 禁止：Blender 側の最低バージョンチェックを削除してビルドを通すこと。適切なコンパイラ更新を優先。

## VS2022 更新済み・PowerShellのJSONエラー修正（2026-10-28）
- ユーザーログでは、Visual Studio Build Tools 2022 は `17.14.12` から `17.14.43` に更新済み（`installationName: VisualStudio/17.14.43+37824.6`）。
- `update_vs2022.ps1` の更新後確認で、Windows PowerShell 5.1が日本語を含む `vswhere -format json -utf8` 出力をパイプ処理中に文字化けさせ、`ConvertFrom-Json` が失敗した。更新失敗ではない。
- `update_vs2022.ps1`、`prepare_build_environment.ps1`、`build_blender.ps1` は、ローカライズを含まない `vswhere -property installationName` のバージョンを取り出す方式に修正済み。
- **再更新は不要**。ユーザーは `git -C "D:\BlenderCustom" pull --ff-only origin main` してから `build_blender.ps1` を実行する。7GBのライブラリは既に取得済み。
- Blender実機ビルドの成功は、修正後のユーザー実行結果を確認するまでは未検証。
