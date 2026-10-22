# Third-party notices

Original Sıkıştırıcı code, documentation and project mascot artwork are licensed under MIT, Copyright (c) 2026 Serkan Aydınlı. The components below retain their own licenses; the root MIT license does not relicense them.

Sıkıştırıcı includes the official 7-Zip 26.04 macOS `7zz` executable, Copyright (C) 1999–2026 Igor Pavlov. It is invoked as a separate process. The executable's code has not been modified; local ad-hoc signing changes its code signature.

- Project: https://www.7-zip.org/
- Official release: https://github.com/ip7z/7zip/releases/tag/26.04
- Original macOS download: https://github.com/ip7z/7zip/releases/download/26.04/7z2604-mac.tar.xz
- Original download SHA-256: `bee04358cbcbc7106273cee0e8d72916db2696c48067a3538c34d8cd6fd16578`
- Corresponding source: https://github.com/ip7z/7zip/tree/26.04
- Complete corresponding source is included at `Vendor/7zip/7z2604-src.tar.xz`, and in the built app at `Contents/Resources/7z2604-src.tar.xz`. SHA-256: `9691944c0fe0d01bb49373a704fb983fd33bc98b1738695179dfbf99ac1734f6`.
- Full LGPL 2.1 text: `Vendor/7zip/COPYING.LGPL-2.1`, copied to `Contents/Resources/7-Zip-LGPL-2.1.txt` in the built app.
- License notices: `Sources/SikistiriciApp/Resources/7-Zip-License.txt`, also included inside the built app at `Contents/Resources/7-Zip-License.txt`.

Most 7-Zip code is licensed under GNU LGPL 2.1 or later; some components use BSD licenses or the additional unRAR restriction. The original upstream license text is included unchanged. 7zz can be replaced and the application rebuilt using `scripts/build-app.sh`.

The unRAR decompression sources may not be used to recreate the proprietary RAR compression algorithm or to develop a RAR (WinRAR) compatible archiver. Sıkıştırıcı does not create RAR archives.

SwiftUI, AppKit and QuickLookUI are Apple system frameworks. No The Unarchiver application code or assets are included. The original Sıkıştırıcı mascot artwork was generated for this project.

## libarchive 3.8.10 (Quick Look preview)

The Quick Look reader statically links official libarchive 3.8.10, under its included BSD-style license notices. Sources: https://github.com/libarchive/libarchive/releases/tag/v3.8.10 . Download: https://github.com/libarchive/libarchive/releases/download/v3.8.10/libarchive-3.8.10.tar.gz . Download SHA-256: `a1bffbe5152cfe869751179e7b16648c87c461cb8c46eee75062efbe164cc57c`. The pinned arm64 static library, public headers, license and rebuild instructions are in `Vendor/libarchive/`. Its license is also included inside the preview extension. System zlib, bzip2, liblzma and iconv are linked from macOS.

Test fixtures are from official libarchive commit `03b426003adf12c1eb4c34e72bedb4c2bf1ba8d3`; their exact source URLs and hashes are in `Tests/ArchiveCoreTests/Fixtures/PROVENANCE.json` with upstream COPYING. They are included in the source/test project, not the app.
