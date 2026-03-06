#!/usr/bin/env bash

echo $MACOS_CODESIGN_IDENTITY
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid
cd flutter; flutter pub get; cd -
~/.cargo/bin/flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h
./build.py --flutter
rm rustdesk-$VERSION.dmg
# security find-identity -v
APP_BUNDLE=$(find ./flutter/build/macos/Build/Products/Release -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_BUNDLE" ]; then
  echo "No macOS .app bundle found."
  exit 1
fi
APP_NAME=$(basename "$APP_BUNDLE")
codesign --force --options runtime -s $MACOS_CODESIGN_IDENTITY --deep --strict "$APP_BUNDLE" -vvv
create-dmg --icon "$APP_NAME" 200 190 --hide-extension "$APP_NAME" --window-size 800 400 --app-drop-link 600 185 rustdesk-$VERSION.dmg "$APP_BUNDLE"
codesign --force --options runtime -s $MACOS_CODESIGN_IDENTITY --deep --strict rustdesk-$VERSION.dmg -vvv
# notarize the rustdesk-${{ env.VERSION }}.dmg
rcodesign notary-submit --api-key-path ~/.p12/api-key.json  --staple rustdesk-$VERSION.dmg
