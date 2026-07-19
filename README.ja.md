# IOSDeGakuseisyo

[English](README.md)

IOSDeGakuseisyoは、Core NFCでNFC-F学生証を読み取り、その非暗号化Type 3 Tagデータを[iOSNFCFCardEmulation](https://github.com/hoshitsugi/iOSNFCFCardEmulation)経由でリーダーに提示する脱獄アプリです。

通常のApp StoreアプリやAltStoreアプリとしてはインストールできません。

## 検証済み環境

| | |
|---|---|
| 端末 | iPhone 8 (`iPhone10,1`) |
| iOS | 16.0.2 (`20A380`) |
| 脱獄 | rootless |
| バックエンド | `org.hoshitsugi.iosnfcfcardemulation` 0.1.0以降 |
| カード | System Code `FE00`、Service Code `1A8B`、ブロック0〜3 |

これ以外の端末とiOSバージョンでの動作は未検証であり、保証しません。

## 使い方

1. iOSNFCFCardEmulationをインストールします。
2. IOSDeGakuseisyoをインストールします。
3. 自分が所有しているか、利用許可を得たカードを読み取ります。
4. 保存したカードを選んで「開始」を押します。終了時は「停止」を押します。

保存するのはRead Without Encryptionで取得できるブロックだけです。保護されたサービスや認証情報は複製しません。

端末内のカードデータはKeychainの鍵で暗号化します。書き出したJSONバックアップは暗号化されません。

## ビルド

WSL2からビルドするには、Theos、`ldid`、iPhoneOS SDKが必要です。

```sh
bash scripts/test.sh
THEOS="$HOME/theos" bash scripts/build.sh
```

生成物は`dist/org.hoshitsugi.iosdegakuseisyo_0.1.0_iphoneos-arm64.deb`です。

## ライセンス

[Apache License 2.0](LICENSE)。学校やカード発行元とは関係のない独立したプロジェクトです。
