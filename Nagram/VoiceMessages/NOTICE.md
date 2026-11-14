# Regram-derived media features

The voice-file converter and native voice draft integration are adapted from
[Regram](https://github.com/RegramDev/Regram-ios), revision
`ff561aa7504d85caf2bfffbc981667d992a9f483`.
Original sources: `Regram/RGVoiceMessages/Sources/RGVoiceFileConverter.swift`
and `Regram/RGVoiceMessages/TelegramUI/ChatControllerVoiceImport.swift`.

Nextgram changes include module naming, localization, engine integration and
security-scoped local-file access. The sticker-pack backup in
`Nagram/MediaActions/Sources/NextgramStickerPackBackup.swift` is adapted from
`Regram/RGStickerSave/Sources/RGStickerPackBackup.swift` at the same revision.
The original portable manifest format is retained for compatibility.

This attribution does not grant a new license. Regram's root at this revision
does not contain a standalone LICENSE file; its README directs distributors
to the repository and dependency licenses. Confirm the applicable upstream
terms before distributing these adapted sources or binaries.
