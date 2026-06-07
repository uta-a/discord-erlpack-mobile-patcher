# Fake Mobile Status Installer CLI

Discord Stable / Canaryを自動検出し、`discord_erlpack/index.js`のみを変更するCUIパッチャーです。
`app.asar`、`_app.asar`、`core.asar`、Vencordのファイルは変更しません。

正式な推奨導線はWindowsのPowerShell版とmacOSのshell script版です。未署名EXEや未署名macOSバイナリは必須にしません。

## 使い方

1. OSに合ったコマンドを実行します。
2. メニューで`Install`を選びます。
3. `stable`または`canary`を選びます。
4. `Success`と表示されたらDiscordを起動します。

元に戻す場合は同じ手順で`Uninstall`を選びます。現在の状態だけ確認したい場合は`View status`を選びます。

状態の意味:

```text
official             公式wrapperのまま
patched              現行パッチ本文と一致
stale-patch          このパッチャー由来の古い、または不完全なパッチ。Installで修復可能
unknown/third-party  他ツールなどが変更済み。安全のため上書きしない
```

`patched`はローカルの`discord_erlpack/index.js`が現行パッチ本文と一致することだけを示します。
Discord上で現在mobile表示になっていることまでは保証しません。

## パッチ内容

このパッチャーは、Discord Gatewayの`IDENTIFY` payloadに含まれる`properties.browser`だけを
`Discord Android`へ置き換えます。`properties.os`と`properties.device`はDiscordデスクトップ
クライアントが送る元の値を維持します。

以前の版では`os`、`browser`、`device`をすべてAndroid値へ置き換えていましたが、現在はE2EE A/Vの
クライアント・デバイス判定との不整合を減らすため、mobile indicatorに必要とされる最小限の
`browser`のみを偽装します。旧3項目偽装済みのwrapperは`stale-patch`として表示され、`Install`で
現行パッチへ修復できます。

参考:

- Mobile indicatorの判定対象は主に`browser`フィールドとされている非公式資料:
  https://luna.gitlab.io/discord-unofficial-docs/docs/mobile_indicator/
- Discord公式のE2EE A/V説明。更新済みクライアントが必要で、検証やデバイス管理に関する注意があります:
  https://support.discord.com/hc/en-us/articles/25968222946071-End-to-End-Encryption-for-Audio-and-Video

Discord側の仕様は変更される可能性があります。この変更はE2EE警告の回避を完全保証するものではありません。

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

Windows版はパッチ適用・削除前に対象Discordが起動中なら強制終了してから続行します。第三者が変更した
`index.js`を上書きすることはありません。このパッチャー由来の古い、または不完全なパッチは
`stale-patch`として表示され、`Install`で現行パッチへ修復できます。

Discord更新後は新しいバージョンへ再度 `install` を実行してください。

## よくある失敗

`Discord stable is still running after stop request`や`Discord canary is still running after stop request`と出る場合は、Discordプロセスの停止に失敗しています。タスクマネージャーから対象Discordを終了してから再実行してください。

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
