# Fake Mobile Status Installer CLI

Windows / macOS の Discord Stable と Discord Canary を自動検出し、
`discord_erlpack/index.js` のみを変更する対話型CUIパッチャーです。

`app.asar`、`_app.asar`、`core.asar`、Vencordのファイルは変更しません。

Windowsでは、未署名EXEを起動せずPowerShell内だけで完結する方式を推奨します。

## Windows PowerShell版

以下のコマンドは最新版の`patcher.ps1`とSHA-256ファイルを一時フォルダへダウンロードし、
一致を確認してからPowerShellスクリプトとして実行します。EXEはダウンロード・起動しません。

```powershell
irm https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.ps1 | iex
```

処理後は、一時フォルダへダウンロードしたファイルを削除します。

非対話で実行する場合:

```powershell
irm https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.ps1 -OutFile run-latest.ps1
.\run-latest.ps1 -Action status
.\run-latest.ps1 -Action install -Channel stable
.\run-latest.ps1 -Action uninstall -Channel canary
```

## PowerShell対話モード

引数なしで起動すると、番号選択式のメニューを表示します。

```text
Fake Mobile Status PowerShell Patcher

What would you like to do?
  1. Install
  2. Uninstall
  3. View status
  4. Quit
Select:
```

操作を選ぶと、検出済みのDiscordだけがバージョン・状態付きで表示されます。

```text
Select Discord installation
  1. stable - app-1.0.100 [official]
  2. canary - app-1.0.200 [patched]
Select:
```

処理後は `Success` または `Failed` と理由を表示します。

## PowerShellローカル実行

リポジトリをclone済みの場合、ダウンロードなしでも実行できます。

```powershell
.\powershell\patcher.ps1
.\powershell\patcher.ps1 -Action status
.\powershell\patcher.ps1 -Action install -Channel stable
.\powershell\patcher.ps1 -Action uninstall -Channel canary
```

通常と異なる場所へDiscordをインストールしている場合は、チャンネルも明示します。

```powershell
.\powershell\patcher.ps1 -Action status -Channel canary -DiscordPath "D:\Apps\DiscordCanary"
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

## テスト

PowerShell版:

```powershell
Invoke-Pester .\powershell\patcher.Tests.ps1
```

Go版:

```powershell
go test ./...
go vet ./...
go build -trimpath -ldflags="-s -w" -o dist/erlpack-patcher.exe ./cmd/erlpack-patcher
```

GitHub ActionsではWindows x64、macOS x64、macOS arm64向けバイナリを生成します。

## Go版の配布時の注意

GitHub Actionsが生成するバイナリは未署名です。一般配布する場合は、Windows版を
Authenticode署名し、macOS版をDeveloper ID署名してnotarizationしてください。

macOS向けのパス検出とビルドには対応していますが、実機上でのパッチ適用は未検証です。

## Goバイナリ版

macOSではGoバイナリ版を使用します。

```text
erlpack-patcher status
erlpack-patcher install
erlpack-patcher uninstall
```

最新版をダウンロードして実行:

```sh
curl -fsSL https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.sh | sh
```

```sh
./run-latest.sh status
./run-latest.sh --channel canary install
```

`v*`タグをpushすると、GitHub ActionsがWindows x64、macOS x64、macOS arm64の
バイナリとSHA-256ファイルをGitHub Releaseへ公開します。
