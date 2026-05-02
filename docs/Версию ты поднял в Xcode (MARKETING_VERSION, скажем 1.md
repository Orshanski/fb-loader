Версию ты поднял в Xcode (MARKETING_VERSION, скажем 1.1). Дальше последовательность из ~7 шагов.

## А. В репо fb-loader/ (исходники):

Запушить правки кода
`git add -A && git commit -m "..." && git push`

    1. Собрать архив

    cd "FB Loader"
    
    xcodebuild -scheme "FB Loader" -configuration Release \
    -archivePath ./build/FBLoader.xcarchive archive

    3. Экспортировать с Developer ID-подписью

    xcodebuild -exportArchive \
    -archivePath ./build/FBLoader.xcarchive \
    -exportPath ./build/export \
    -exportOptionsPlist ./build/export-options.plist

    4. Нотаризовать

    cd build/export
    ditto -c -k --keepParent "FB Loader.app" "FB Loader.zip"
    xcrun notarytool submit "FB Loader.zip" --keychain-profile FBLoaderNotary --wait

Ждёшь Accepted.

    5. Staple

```xcrun stapler staple "FB Loader.app"```

    5. Сделать DMG

    create-dmg --volname "FB Loader" --window-size 500 350 \
    --icon "FB Loader.app" 125 175 \
    --app-drop-link 375 175 \
    "FB Loader-1.1.dmg" "FB Loader.app"

    7. Создать GitHub Release

    cd /Users/alexey/Documents/code/fb-loader
    
    gh release create v1.1 "FB Loader/build/export/FB Loader-1.1.dmg" \
    --title "1.1" --notes "Приложение закрывается по клику. Изменен размер карточки книги по умолчанию"

## B. В репо homebrew-fb-loader/ (cask-меню):

7. Получить sha256 нового DMG

```shasum -a 256 "FB Loader/build/export/FB Loader-1.1.dmg"```

    8. Открыть ~/Documents/code/homebrew-fb-loader/Casks/fb-loader.rb, поменять две строки:

    version "1.1"
    sha256 "новый-хеш"

    10. Запушить cask

```git add -A && git commit -m "fb-loader 1.1" && git push```

Готово. Пользователи получают апдейт командой brew upgrade --cask fb-loader.