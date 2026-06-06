# PowerShell + shell script redesign

## 結論

このプロジェクトの正式な配布方針は、Goバイナリ中心ではなく、Windows向けのPowerShell版とmacOS向けのshell script版を主軸にする。

理由は、パッチャーの実処理が限定的であり、未署名EXEや未署名macOSバイナリを配布するより、OS標準のスクリプト実行環境を使う方が導入障壁と警告リスクを下げられるため。

## 目的

- WindowsとmacOSの両方に対応する
- EXEや署名なしバイナリを必須にしない
- Discord Stable / Canaryを自動検出する
- `discord_erlpack/index.js`のみを変更する
- `app.asar`、`_app.asar`、`core.asar`、Vencordのファイルは変更しない
- Vencordの更新やapp.asar変更に巻き込まれにくい配布形にする
- Vencord Installer CLIに近い、選択しやすいCUIを提供する

## 採用する構成

```text
powershell/
  patcher.ps1        # Windows本体
  test.ps1           # Windows向け自己完結テスト

shell/
  patcher.sh         # macOS本体
  test.sh            # macOS向け自己完結テスト

run-latest.ps1       # Windows用ランチャー
run-latest.sh        # macOS用ランチャー

docs/
  powershell-shell-redesign.md
```

Windowsでは`run-latest.ps1`がGitHub Releaseから`patcher.ps1`とSHA-256ファイルをTempへ取得し、ハッシュ検証後にPowerShellスクリプトとして実行する。

macOSでは`run-latest.sh`がGitHub Releaseから`patcher.sh`とSHA-256ファイルをTempへ取得し、ハッシュ検証後に`sh`で実行する。

## ユーザー向け実行方法

Windows:

```powershell
irm https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.ps1 | iex
```

macOS:

```sh
curl -fsSL https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.sh | sh
```

非対話実行:

```powershell
.\run-latest.ps1 -Action status
.\run-latest.ps1 -Action install -Channel stable
.\run-latest.ps1 -Action uninstall -Channel canary
```

```sh
./run-latest.sh status
./run-latest.sh install --channel stable
./run-latest.sh uninstall --channel canary
```

## Go版との位置づけ

Go版は削除する。

理由:

- Windowsでは未署名EXEがSmart App ControlやDefenderの警告対象になりやすい
- macOSではGatekeeper、Developer ID署名、notarizationの問題がある
- 今回の処理内容に対して、バイナリ配布の運用コストが大きい
- 配布導線が複数あると、ユーザーがどれを使うべきか迷いやすい

正式な推奨導線はPowerShell + shell scriptに一本化する。

## Node.js版との比較

Node.js版は、矢印キーUIや共通コード化では優れている。

ただし、ユーザー側にNode.jsが必要になる。Node.jsを同梱して配布する場合は、結局バイナリ配布になり、WindowsのSmart App ControlやmacOSのGatekeeper問題に戻る。

今回の処理は、ファイル検出、状態判定、バックアップ、書き換え、復元が中心であり、Node.jsを要求するほど複雑ではない。

結論として、Node.js版は不要。GUI化や複雑なUIが必要になった段階で再検討する。

## CUI設計

対話モードでは次の順で選択させる。

1. 操作を選択
   - Install
   - Uninstall
   - View status
   - Quit
2. 対象Discordを選択
   - Stable
   - Canary

検出結果には、チャンネル、アプリバージョン、現在の状態を表示する。

例:

```text
Select Discord installation
  > stable - app-1.0.9240 [official]
    canary - app-1.0.982 [patched]
```

Windows PowerShellでは、可能なら矢印キー、Enter、Escを使う。非対話環境やリダイレクト時は番号入力へフォールバックする。

macOS shell scriptでは、まず番号入力を確実に実装する。矢印キー選択は`stty`と`read -rsn1`で実装可能だが、端末差分が出やすいため、初期版では任意改善扱いにする。

## パッチ対象

変更するファイルは以下のみ。

```text
<Discord root>/<app version>/modules/discord_erlpack-*/discord_erlpack/index.js
```

対象外:

- `app.asar`
- `_app.asar`
- `core.asar`
- Vencordのファイル
- BetterDiscord / Equicordのファイル
- Discord設定ファイル

## 状態判定

`index.js`の内容を読み、以下の3状態に分類する。

- `official`: Discord公式の薄いwrapper
- `patched`: このパッチャーが生成したwrapper
- `unknown/third-party`: それ以外

`unknown/third-party`は上書きしない。これはVencordや他ツールが同じ箇所を触った場合に破壊しないため。

## install動作

1. 対象Discordプロセスが起動中なら中断する
2. Stable / Canaryの対象`index.js`を検出する
3. 状態が`official`であることを確認する
4. 公式wrapperをバージョン別バックアップへ保存する
5. patched wrapperを書き込む
6. 書き込み後にSHA-256で検証する
7. 成功または失敗理由を表示する

## uninstall動作

1. 対象Discordプロセスが起動中なら中断する
2. 対象`index.js`が`patched`であることを確認する
3. バージョン別バックアップが存在することを確認する
4. バックアップが`official`であることを確認する
5. 公式wrapperへ復元する
6. 書き込み後にSHA-256で検証する
7. 成功または失敗理由を表示する

## バックアップ場所

Windows:

```text
%LOCALAPPDATA%\FakeMobileStatus\powershell-patcher\backups\<channel>\<app-version>\discord_erlpack-index.js
```

macOS:

```text
~/Library/Application Support/FakeMobileStatus/shell-patcher/backups/<channel>/<app-version>/discord_erlpack-index.js
```

バックアップはチャンネルとアプリバージョンで分ける。Discord更新後に新しい`app-*`ディレクトリが作られても、旧バージョンのバックアップと混ざらないようにするため。

## 自動検出パス

Windows:

```text
Stable: %LOCALAPPDATA%\Discord
Canary: %LOCALAPPDATA%\DiscordCanary
```

macOS:

```text
Stable: ~/Library/Application Support/discord
Canary: ~/Library/Application Support/discordcanary
```

カスタムパス指定も残す。

Windows:

```powershell
.\patcher.ps1 -Action status -Channel canary -DiscordPath "D:\Apps\DiscordCanary"
```

macOS:

```sh
./patcher.sh status --channel canary --discord-path "$HOME/Applications/Discord Canary"
```

## Release成果物

GitHub Releaseには以下を含める。

```text
run-latest.ps1
run-latest.sh
patcher.ps1
patcher.ps1.sha256
patcher.sh
patcher.sh.sha256
```

GoバイナリはRelease成果物に含めない。workflowとREADMEからもGoバイナリ生成・実行導線を削除する。

## GitHub Actions方針

必要なジョブ:

- Windowsで`powershell/test.ps1`を実行
- macOSで`shell/test.sh`を実行
- `patcher.ps1` / `patcher.sh`のSHA-256を生成
- `v*`タグpush時にReleaseへ成果物をアップロード

Go test / Go build jobは持たない。

## セキュリティ方針

- Releaseから取得した本体スクリプトはSHA-256で検証する
- Tempディレクトリはランダム名で作成する
- 実行後はTempディレクトリを削除する
- Discordディレクトリ外へ解決されるパスは拒否する
- `unknown/third-party` wrapperは上書きしない
- Discord起動中の書き換えは拒否する
- 公式backup以外からのuninstall復元は拒否する

## 実装順序

1. 既存PowerShell版を正式Windows実装として整理する
2. macOS向け`shell/patcher.sh`を追加する
3. `run-latest.sh`をGoバイナリDL方式から`shell/patcher.sh`DL方式へ変更する
4. Release workflowに`patcher.sh`とSHA-256を追加する
5. READMEをPowerShell + shell script中心に書き換える
6. Go版を削除し、workflowとREADMEからバイナリ導線を消す

## 受け入れ基準

- Windowsで`irm ...run-latest.ps1 | iex`からinstall / uninstall / statusが動く
- macOSで`curl ...run-latest.sh | sh`からinstall / uninstall / statusが動く
- Stable / Canaryを自動検出できる
- `unknown/third-party` wrapperを上書きしない
- Discord起動中は変更しない
- `app.asar`、`_app.asar`、`core.asar`、Vencordのファイルを変更しない
- Release assetにPowerShell版とshell版の本体、SHA-256、ランチャーが含まれる
- READMEの推奨導線がPowerShell + shell scriptになっている

## 未解決事項

- macOS実機で`discord_erlpack/index.js`の場所とwrapper内容を確認する必要がある
- macOSでDiscordプロセス名をStable / Canaryごとに正確に判定する必要がある
- 既存Go版ユーザー向けの移行説明はREADMEでPowerShell + shell script導線へ集約する
