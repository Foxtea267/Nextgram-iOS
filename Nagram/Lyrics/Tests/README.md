# Online lyrics regression checks

Run from the repository root with the macOS Swift toolchain:

```sh
xcrun swiftc -parse-as-library Nagram/Lyrics/Sources/*.swift Nagram/Lyrics/Tests/OnlineLyricsRegression.swift -o /tmp/nextgram-lyrics-regression
/tmp/nextgram-lyrics-regression
```

The executable installs an isolated URLProtocol into the lyrics HTTP session; no live requests or accounts are used. It checks successful memory/disk cache restoration (including a separate process), forced refresh, retention after failed refresh, 404 versus service failure, artist separators/order, rejection of different versions/durations, and word timing serialization. It removes its own uniquely named cache file on completion. App validation still requires a complete simulator build.
