# Harvest-SwiftUI-VideoDetector

📹 Video image/text recognizers written in SwiftUI + Harvest + iOS Vision + SwiftyTesseract.

## Examples

| Face (iOS Vision) | Text Rect (iOS Vision) |
|---|---|
| <img src="Assets/ios-vision-face-recognition.jpg" width="750"> | <img src="Assets/ios-vision-text-rect.jpg" width="750"> |


| Text Recognition (iOS Vision) | Text Recognition (Tesseract, Japanese) |
|---|---|
| <img src="Assets/ios-vision-text-recognition.jpg" width="750"> | <img src="Assets/tesseract-japanese.jpg" width="750"> |

### Caveats & 🆘 Need Help!

- There is a weird **codesign issue** where app can't get installed without adding `codesign --force` in Run Script as a workaround, so **try build & device-install several times** even Xcode may prompt install error.
- Text recognition works for landscape mode only (need help for portrait detection!)
- Tesseract 4.0.0 + Japanese text recognition is super slow & poor at the moment.

## License

[MIT](LICENSE)