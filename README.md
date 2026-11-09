# Wolke

A small macOS desktop player for SoundCloud in Safari, with a sleeping orange cat curled around the cover.

![Wolke’s horizontal desktop widget on a blue macOS desktop. The orange cat wraps around the track cover.](docs/wolke-desktop.png)

**Free local beta** · Apple silicon · macOS 14 or later · Safari · [Apache 2.0](LICENSE)

Wolke follows the SoundCloud track playing in Safari. The desktop widget shows its cover, artist, and running time. Use it to play or pause, jump 15 seconds, skip tracks, or toggle a like. The playlist button opens SoundCloud’s playlist chooser in Safari.

| Size | Layout |
| :--- | :--- |
| **1×1** | Compact cover and two rows of controls |
| **2×1** | Horizontal player with cover and controls side by side |
| **2×2** | Larger artwork and a full row of controls |

## Install

1. Download `Wolke-1.7.zip` from the [Wolke 1.7 release](https://github.com/leluxIceIce/Wolke/releases/tag/v1.7), unzip it, move **Wolke.app** into **Applications**, and open it. Wolke runs in the menu bar. Use **Player anzeigen** (Show Player) there if you want its compact window.
2. In Safari, open **Settings → Advanced** and enable **Show features for web developers**. Under **Developer**, enable **Allow unsigned extensions** for this Safari session. This is a session-wide setting and Safari resets it when you quit. [Apple’s Safari setup guide](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)
3. In **Safari → Settings → Extensions**, enable **Wolke**. Grant access to **soundcloud.com**. That permission also covers `soundcloud.com/discover`.
4. Reload your SoundCloud tab with **⌘R** and start a track. Right-click the desktop, choose **Edit Widgets**, and add **Wolke** in your preferred size.

Keep a single copy of Wolke in Applications and quit older copies before updating. The downloadable beta is signed to run locally. It is distributed outside the App Store and is not notarized.

## How it works

- **Use your existing SoundCloud session.** Wolke reads the player on SoundCloud pages. Your sign-in stays in Safari. The Safari extension and desktop widget exchange playback state and commands with the local Wolke app over loopback.
- **Close the source tab.** With **Allow All Auto-Play** enabled for SoundCloud, Wolke can try to resume a playing track at the last known position in a background Safari tab. Expect a short load on handoff. Quitting Safari ends playback.
- **Use the Safari toolbar too.** Click Wolke’s cat icon on a SoundCloud tab for a compact player in the browser. If the icon is hidden, add it through **View → Customize Toolbar**.

## Build from source

You need Xcode on an Apple silicon Mac. Select Xcode as the active developer directory, then run:

```sh
sh scripts/build.sh
```

The script creates a local bridge key on first build and leaves the verified archive in `dist/`. The key is ignored by Git. To work in Xcode, run the script once and then open `Wolke.xcodeproj`.

Run the browser-side tests with Node.js:

```sh
node Tests/player.test.cjs
node Tests/handoff.test.cjs
```

## License

Wolke’s source code and original cat artwork are licensed under [Apache 2.0](LICENSE). See [NOTICE](NOTICE) for third-party materials.

Wolke is an independent companion app. The SoundCloud wordmark identifies the playback source. SoundCloud branding and the track artwork in the screenshot retain their respective rights. [SoundCloud attribution assets](https://developers.soundcloud.com/docs/api/buttons-logos)
