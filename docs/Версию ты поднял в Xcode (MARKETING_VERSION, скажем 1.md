Версию ты поднял в Xcode (MARKETING_VERSION, скажем 1.1). Дальше последовательность шагов.

## А. В репо fb-loader/ (исходники):

1. Запушить правки кода

```
cd ~/code/fb-loader
git add -A && git commit -m "..." && git push
```

2. Собрать архив

```
cd "FB Loader"
xcodebuild -scheme "FB Loader" -configuration Release \
  -archivePath ./build/FBLoader.xcarchive archive
```

3. Экспортировать с Developer ID-подписью

```
xcodebuild -exportArchive \
  -archivePath ./build/FBLoader.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ./build/export-options.plist
```

4. Нотаризовать

```
cd build/export
ditto -c -k --keepParent "FB Loader.app" "FB Loader.zip"
xcrun notarytool submit "FB Loader.zip" --keychain-profile FBLoaderNotary --wait
```

Ждёшь Accepted.

Если ругается `No Keychain password item found for profile: FBLoaderNotary` — на этом маке нет профиля нотаризации. Миграция его не переносит, на новом маке он создаётся заново:

- На account.apple.com → «Вход и безопасность» → «Пароли приложений» выпустить новый пароль (старый посмотреть нельзя).
- Сохранить профиль, пароль ввести по запросу, а не аргументом:

  ```
  xcrun notarytool store-credentials FBLoaderNotary \
    --apple-id <Apple ID разработчика> \
    --team-id N8J32835MC
  ```

- Проверить: `xcrun notarytool history --keychain-profile FBLoaderNotary` — без ошибки, значит работает.

Сертификат «Developer ID Application: Alexey Orshanski (N8J32835MC)» нужен для шага 3; проверить, есть ли он: `security find-identity -v -p codesigning`.

5. Staple

```
xcrun stapler staple "FB Loader.app"
```

6. Сделать DMG

```
create-dmg --volname "FB Loader" --window-size 500 350 \
  --icon "FB Loader.app" 125 175 \
  --app-drop-link 375 175 \
  "FB Loader-1.1.dmg" "FB Loader.app"
```

7. Создать GitHub Release

```
cd ~/code/fb-loader
gh release create v1.1 "FB Loader/build/export/FB Loader-1.1.dmg" \
  --title "1.1" --notes "Описание изменений"
```

## B. В репо homebrew-fb-loader/ (cask-меню):

8. Получить sha256 нового DMG

```
shasum -a 256 "FB Loader/build/export/FB Loader-1.1.dmg"
```

9. Открыть `~/code/homebrew-fb-loader/Casks/fb-loader.rb`, поменять две строки:

```
version "1.1"
sha256 "новый-хеш"
```

10. Запушить cask (ВАЖНО: сначала перейти в репо tap'а!)

```
cd ~/code/homebrew-fb-loader
git add Casks/fb-loader.rb && git commit -m "fb-loader 1.1" && git push
```

Готово. Пользователи получают апдейт командой `brew update && brew upgrade --cask fb-loader`.
