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

## VS2022 更新後も MSVC エラー継続（2026-10-28）
- VS 2022 製品バージョン `17.14.43` が確認されたのに、CMake 再実行が「MSVC 17.14.14 以上が必要」のまま停止。
- 2度目のログには `The CXX compiler identification` が出ず、CMake に更新前のコンパイラ情報がキャッシュされている可能性が高い。
- `custom_tools/build_blender.ps1` で、初回の設定失敗で `Blender.sln` がない場合、または CMake が `19.44.35216` 未満のコンパイラを記録している場合に限り、当該Blenderビルドフォルダの `CMakeCache.txt` と `CMakeFiles` を削除して自動再検出するよう修正。
- キャッシュの `CMAKE_HOME_DIRECTORY` が `D:\BlenderCustom` でない場合は削除せずエラー停止する安全対策。
- 取得済み依存ライブラリ、本体ソース、通常版Blenderの設定は変更しない。
- ユーザーが GitHub から Pull 後に `build_blender.ps1` を再実行して確認する。

## 初回ビルド・起動成功（2026-10-28）
- ユーザーが `D:\BlenderCustom\custom_tools\build_blender.ps1` 実行後、`BUILD SUCCESS` と `D:\build_windows_x64_vc17_Release\bin\Release\blender.exe` を確認した。
- ユーザーが上記 `blender.exe` を起動し、起動成功を報告した。
- 現時点ではBlender本体は初回ビルド・起動確認済みで、DesignDoll Animation Exporterなどの独自アドオンはまだBlenderCustomに統合していない。
- フォルダ整理希望あり：`D:\Blender\BlenderCustom` と `D:\Blender\Build` 等にまとめたい。ただし元の `D:\BlenderCustom` と `D:\build_windows_x64_vc17_Release` を単純移動するとCMakeの絶対パスが壊れるため、作業前に安全な移行方法を選ぶ。ユーザーの許可なくフォルダ移動しない。

## フォルダ整理手順（2026-10-28 改訂・実機での移行結果は未確認）
- ユーザーからD:直下のジャンクション2つが残ることへの明確な異議あり。**互換ジャンクション方式は撤回**。
- `custom_tools/organize_folders.ps1` は旧実体 `D:\BlenderCustom` を `D:\Blender\BlenderCustom` に、旧ビルド `D:\build_windows_x64_vc17_Release` を `D:\Blender\Build` に同一NTFSボリューム内で物理移動する。
- 旧ルートのフォルダ、ジャンクションは作成しない。物理データのコピーや新規依存ライブラリのダウンロードはしない。
- CMakeのソース/ビルド絶対パスが変わるため `CMakeCache.txt`, `CMakeFiles` と `Blender.sln`（生成設定のみ）を移動後に削除し、次のビルドで再生成する。**この再生成に伴い大規模な再コンパイルが発生する可能性あり。** コンパイル済みオブジェクトや実行ファイルはそのまま残す。
- 旧フォルダと移動先が同時に存在する場合や、予期せぬリンクがある場合は安全のため停止する。改造版Blenderとコンパイラは終了して実行。
- 実行前: `git -C "D:\BlenderCustom" pull --ff-only origin main`。
- 移行コマンド: `powershell -NoProfile -ExecutionPolicy Bypass -File "D:\BlenderCustom\custom_tools\organize_folders.ps1"`。
- 移行後のGit操作: `git -C "D:\Blender\BlenderCustom" pull --ff-only origin main`。
- 移行後ビルド: `powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Blender\BlenderCustom\custom_tools\build_blender.ps1"`（スクリプト内で `make.bat 2022b builddir "D:\Blender\Build"`）。
- 移行後の既存実行ファイル: `D:\Blender\Build\bin\Release\blender.exe`。起動の有無はユーザー実機確認が必要。
- **移行自体はまだユーザーPCで未実施／未検証。** 移行を実行したと報告されるまでは成功とは断定しない。

- 2026-10-28 初回の `organize_folders.ps1` 実行は `変数 HOME は読み取り専用` で、**フォルダ移動前に**停止。原因は `$home` 変数名がPowerShell組み込みの `$HOME` と競合したため。`$cmakeHomeLine` に変更し GitHub commit `ec6fce624e19daf401b7bcc961173f75429aa723` で修正。移行はまだ実行成功していない。

## フォルダ整理完了（2026-10-28 ユーザー実機確認）
- ユーザーが `custom_tools/organize_folders.ps1` 実行、`ORGANIZATION SUCCESS` を報告。
- 実体ソースは `D:\Blender\BlenderCustom`、ビルド成果物は `D:\Blender\Build` に移動済み。
- 出力は `Old top-level folders: absent. No junctions created.`、Gitチェック `true`。
- Blender実行ファイルは `D:\Blender\Build\bin\Release\blender.exe` に存在。**移動後の起動可否は未確認**（移動前は起動確認済み）。
- 次回のソース更新は `git -C "D:\Blender\BlenderCustom" pull --ff-only origin main`。
- 次回ビルドは `powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Blender\BlenderCustom\custom_tools\build_blender.ps1"`。CMakeキャッシュ削除済みなので再設定と再コンパイルが発生する可能性あり。
- **旧パス `D:\BlenderCustom` 及び `D:\build_windows_x64_vc17_Release` は現在存在しない**。以降、操作案内では使わない。

- 2026-10-28 ユーザーが移動後の `D:\Blender\Build\bin\Release\blender.exe` の正常起動を確認。これによりフォルダ整理と起動確認は完了。次工程はDesignDoll用アドオン等の独自機能の取り込み（まだ未実装）。

## DesignDoll Animation PNG Export アドオン取り込み（2026-10-28）
- ChatGPT過去生成ファイル `design_doll_animation_export.py`（417行、`bl_info` version 1.0.0）をファイルライブラリから回収し、Python構文検査済み。
- アドオンを `scripts/addons_core/design_doll_animation_export.py` に追加。通常版Blenderを変更しない。
- 旧プロジェクト名を含むデフォルト出力絶対パスだけ `//render_png`（.blendからの相対パス）に変更。その他の処理は元コードのまま。
- リビルドせず現行の `D:\Blender\Build\bin\Release\blender.exe` に取り込むため `custom_tools/install_design_doll_animation_export.ps1` を追加。
- スクリプトはこの改造版Blenderに `bpy.utils.script_paths(subdir='addons_core')` を問い合わせ、D:\Blender\Build 内にあるランタイムのaddons_coreへファイルをコピー。SHA256照合後、BlenderCustomのバックグラウンド起動でaddon_utils.enableによる一時的な登録を検証する。
- **ユーザーPCでのインストール成功・動作確認はまだ未確認**。実行結果 `ADDON INSTALL SUCCESS` の確認待ち。
- ユーザー実行コマンド: `git -C "D:\Blender\BlenderCustom" pull --ff-only origin main`、次に `powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Blender\BlenderCustom\custom_tools\install_design_doll_animation_export.ps1"`。
- 実行後はBlenderCustomの編集→プリファレンス→アドオンで `DesignDoll Animation PNG Export` を有効化。アドオン機能は3DビューNパネルの `アニメ出力`。
- Pythonアドオンのコピーだけなので、この導入には本体再コンパイルは不要。通常版Blenderとは独立だが、Blenderのユーザー設定フォルダはバージョンで共有されうるためインストーラーはユーザー設定を自動変更しない。
