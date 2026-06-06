# Fake Mobile Status Installer CLI

Discord Stable / Canaryを自動検出し、`discord_erlpack/index.js`のみを変更するCUIパッチャーです。
`app.asar`、`_app.asar`、`core.asar`、Vencordのファイルは変更しません。

正式な推奨導線はWindowsのPowerShell版とmacOSのshell script版です。未署名EXEや未署名macOSバイナリは必須にしません。

## 使い方

1. Discordを完全に終了します。
2. OSに合ったコマンドを実行します。
3. メニューで`Install`を選びます。
4. `stable`または`canary`を選びます。
5. `Success`と表示されたらDiscordを起動します。

元に戻す場合は同じ手順で`Uninstall`を選びます。現在の状態だけ確認したい場合は`View status`を選びます。

状態の意味:

```text
official             公式wrapperのまま
patched              mobile表示パッチ適用済み
unknown/third-party  他ツールなどが変更済み。安全のため上書きしない
```

## Windows

最新版の`patcher.ps1`とSHA-256ファイルをTempへダウンロードし、検証後にPowerShellスクリプトとして実行します。EXEはダウンロード・起動しません。

```powershell
irm https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.ps1 | iex
```

対話モードは矢印キーで選択できます。非対話で実行する場合:

```powershell
irm https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.ps1 -OutFile run-latest.ps1
.\run-latest.ps1 -Action status
.\run-latest.ps1 -Action install -Channel stable
.\run-latest.ps1 -Action uninstall -Channel canary
```

StableではなくCanaryへ適用する場合:

```powershell
.\run-latest.ps1 -Action install -Channel canary
```

## macOS

最新版の`patcher.sh`とSHA-256ファイルをTempへダウンロードし、検証後に`sh`で実行します。macOSバイナリはダウンロード・起動しません。

```sh
curl -fsSL https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.sh | sh
```

対話モードはTTYでは矢印キーで選択できます。非対話で実行する場合:

```sh
curl -fsSL https://github.com/uta-a/discord-erlpack-mobile-patcher/releases/latest/download/run-latest.sh -o run-latest.sh
sh run-latest.sh status
sh run-latest.sh install --channel stable
sh run-latest.sh uninstall --channel canary
```

StableではなくCanaryへ適用する場合:

```sh
sh run-latest.sh install --channel canary
```

## 対話モード

引数なしで起動すると、操作と対象Discordを順に選択します。
Windows PowerShell版は現在の矢印キーUIを維持しています。macOS shell版もTTYでは矢印キーUIを使い、非対話環境では番号入力へ切り替えます。

```text
Fake Mobile Status shell patcher

What would you like to do?
Use Up/Down arrows and Enter. Esc cancels.
  > Install
    Uninstall
    View status
    Quit
```

```text
Select Discord installation
Use Up/Down arrows and Enter. Esc cancels.
  > stable - app-1.0.100 [official]
    canary - app-1.0.200 [patched]
```

処理後は`Success`または`Failed`と理由を表示します。

## ローカル実行

リポジトリをclone済みの場合、ダウンロードなしでも実行できます。

```powershell
.\powershell\patcher.ps1
.\powershell\patcher.ps1 -Action status
.\powershell\patcher.ps1 -Action install -Channel stable
.\powershell\patcher.ps1 -Action uninstall -Channel canary
```

```sh
sh shell/patcher.sh
sh shell/patcher.sh status
sh shell/patcher.sh install --channel stable
sh shell/patcher.sh uninstall --channel canary
```

通常と異なる場所へDiscordをインストールしている場合:

```powershell
.\powershell\patcher.ps1 -Action status -Channel canary -DiscordPath "D:\Apps\DiscordCanary"
```

```sh
sh shell/patcher.sh status --channel canary --discord-path "$HOME/Applications/Discord Canary"
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

## よくある失敗

`Discord stable is running`や`Discord canary is running`と出る場合は、Discordがまだ起動しています。タスクトレイやメニューバーから終了してから再実行してください。

`unknown/third-party`と出る場合は、対象の`discord_erlpack/index.js`が公式状態でもこのパッチャーの状態でもありません。Vencordや他ツールのファイルを壊さないため、自動では上書きしません。

Discord更新後にmobile表示ではなくなった場合は、新しい`app-*`ディレクトリへDiscordが更新されています。もう一度`Install`を実行してください。

## テスト

```powershell
.\powershell\test.ps1
```

```sh
sh shell/test.sh
```

`v*`タグをpushすると、GitHub Actionsが`run-latest.ps1`、`run-latest.sh`、`patcher.ps1`、`patcher.sh`、各SHA-256ファイルをGitHub Releaseへ公開します。
