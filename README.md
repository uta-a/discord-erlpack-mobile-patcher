# Fake Mobile Status Installer CLI

Windows / macOS の Discord Stable と Discord Canary を自動検出し、
`discord_erlpack/index.js` のみを変更する対話型CUIパッチャーです。

`app.asar`、`_app.asar`、`core.asar`、Vencordのファイルは変更しません。

## 対話モード

引数なしで起動すると、Vencord Installer CLIに近い選択UIを表示します。

```text
Fake Mobile Status Installer dev

Use the arrow keys to navigate: ↓ ↑ → ←
? What would you like to do? (Press Enter to confirm):
  ▸ Install
    Uninstall
    View status
    Quit
```

操作を選ぶと、検出済みのDiscordだけがバージョン・状態付きで表示されます。

```text
? Select Discord installation to Install (Press Enter to confirm):
  ▸ Discord Stable - app-1.0.100 [NOT PATCHED]
    Discord Canary - app-1.0.200 [PATCHED]
```

処理後は `Success` または `Failed` と理由を表示し、Enterを押すまでウィンドウを
閉じません。エクスプローラーから直接起動した場合も結果を確認できます。

## 非対話モード

スクリプトや自動化では従来どおりコマンドを指定できます。
`--channel` の既定値は `auto` です。`install` / `uninstall` ではStableを優先し、
StableがなければCanaryを選びます。`status` は検出済みの全チャンネルを表示します。

```text
erlpack-patcher.exe status
erlpack-patcher.exe install
erlpack-patcher.exe uninstall

erlpack-patcher.exe --channel stable install
erlpack-patcher.exe --channel canary uninstall
```

通常と異なる場所へDiscordをインストールしている場合は、チャンネルも明示します。

```text
erlpack-patcher.exe --channel canary --discord-path "D:\Apps\DiscordCanary" status
```

自動検出する場所:

```text
Windows Stable:  %LOCALAPPDATA%\Discord
Windows Canary:  %LOCALAPPDATA%\DiscordCanary
macOS Stable:    ~/Library/Application Support/discord
macOS Canary:    ~/Library/Application Support/discordcanary
```

パッチ適用・削除前に対象Discordを完全終了してください。第三者が変更した
`index.js` や、適用後に変更されたパッチを上書きすることはありません。

Discord更新後は新しいバージョンへ再度 `install` を実行してください。

## ローカルビルド

Go 1.24以降を使用します。

```powershell
go test ./...
go vet ./...
go build -trimpath -ldflags="-s -w" -o dist/erlpack-patcher.exe ./cmd/erlpack-patcher
```

GitHub ActionsではWindows x64、macOS x64、macOS arm64向けバイナリを生成します。

## 配布時の注意

GitHub Actionsが生成するバイナリは未署名です。一般配布する場合は、Windows版を
Authenticode署名し、macOS版をDeveloper ID署名してnotarizationしてください。

macOS向けのパス検出とビルドには対応していますが、実機上でのパッチ適用は未検証です。

## 最新版をダウンロードして実行

GitHub Releaseの最新版を一時ディレクトリへダウンロードし、公開されたSHA-256と
一致することを確認してから起動できます。終了後、ダウンロードしたファイルは削除されます。

Windows PowerShell:

```powershell
irm https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.ps1 | iex
```

macOS:

```sh
curl -fsSL https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.sh | sh
```

リポジトリ内のスクリプトから非対話コマンドを渡す場合:

```powershell
.\run-latest.ps1 status
.\run-latest.ps1 --channel canary install
```

```sh
./run-latest.sh status
./run-latest.sh --channel canary install
```

`v*`タグをpushすると、GitHub ActionsがWindows x64、macOS x64、macOS arm64の
バイナリとSHA-256ファイルをGitHub Releaseへ公開します。
