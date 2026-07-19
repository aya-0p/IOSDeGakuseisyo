# IOSDeGakuseisyo

[日本語](README.ja.md)

IOSDeGakuseisyo is a jailbreak app that reads an NFC-F student ID card with Core NFC and presents its unencrypted Type 3 Tag data through [iOSNFCFCardEmulation](https://github.com/hoshitsugi/iOSNFCFCardEmulation).

It cannot be installed as a normal App Store or AltStore app.

## Tested environment

| | |
|---|---|
| Device | iPhone 8 (`iPhone10,1`) |
| iOS | 16.0.2 (`20A380`) |
| Jailbreak | rootless |
| Backend | `org.hoshitsugi.iosnfcfcardemulation` 0.1.0 or later |
| Card profile | System Code `FE00`, Service Code `1A8B`, blocks 0–3 |

Other devices and iOS versions have not been tested and are not guaranteed to work.

## Usage

1. Install iOSNFCFCardEmulation.
2. Install the IOSDeGakuseisyo package.
3. Scan a card you own or have permission to use.
4. Select the saved card and tap Start. Tap Stop when finished.

Only blocks available through Read Without Encryption are stored. Protected services and authentication data are not copied.

Cards stored on the device are encrypted with a Keychain-backed key. Exported JSON backups are not encrypted.

## Build

Building from WSL2 requires Theos, `ldid`, and an iPhoneOS SDK.

```sh
bash scripts/test.sh
THEOS="$HOME/theos" bash scripts/build.sh
```

The package is written to `dist/org.hoshitsugi.iosdegakuseisyo_0.1.0_iphoneos-arm64.deb`.

## License

[Apache License 2.0](LICENSE). Independent project; not affiliated with any school or card issuer.
