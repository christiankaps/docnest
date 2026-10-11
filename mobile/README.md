# DocNest Mobile

Independent iPhone app for personal paperwork. Requires Xcode 27 or later and iOS 27 or later. Current implementation: a SwiftUI Hello World screen with a local app icon and English string catalog.

Open `DocNestMobile.xcodeproj`, choose an iPhone simulator, and run. Physical-device builds require selecting your own development team in Signing & Capabilities.

Run commands from this folder:

```sh
make help
make verify
```

`project.yml` is the project configuration source. After changing it, run `make generate` with XcodeGen installed. The generated Xcode project is included so ordinary builds do not require XcodeGen. Build output stays in `.build/`.

The planned initial delivery uses a local-only, app-private library. See [PROJECT.md](PROJECT.md) for the consolidated product concept, [ARCHITECTURE.md](ARCHITECTURE.md) for technical boundaries and open engineering decisions, and [PLAN.md](PLAN.md) for sequential implementation and verification. Only the Hello World increment is complete.

## Icon

`Design/AppIconSource.png` is a copied DocNest master icon. The iOS asset is an opaque PNG conversion of that image. Both files are local; builds require no external project files.
