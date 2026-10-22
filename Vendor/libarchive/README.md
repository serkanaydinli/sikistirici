# libarchive 3.8.10

Official source: https://github.com/libarchive/libarchive/releases/download/v3.8.10/libarchive-3.8.10.tar.gz
Source tarball SHA-256: a1bffbe5152cfe869751179e7b16648c87c461cb8c46eee75062efbe164cc57c
Included static library SHA-256: 20c80b78e06467e38378524aa339bd21148444a3d90132728c3c7d4a143eb275
Architecture: arm64; deployment target macOS 14.

From the unpacked source directory, reproduce with:

```sh
MACOSX_DEPLOYMENT_TARGET=14.0 CFLAGS='-O2 -mmacosx-version-min=14.0' ./configure --disable-shared --enable-static --disable-bsdtar --disable-bsdcat --disable-bsdcpio --disable-bsdunzip --disable-acl --disable-xattr --without-openssl --without-xml2 --without-expat --without-lz4 --without-zstd
make -j4
```

Copy `.libs/libarchive.a` to `lib/`, `libarchive/archive.h` and `libarchive/archive_entry.h` to `include/`, and `COPYING` here. The static archive may differ byte-for-byte across toolchain/build path versions; verify functional tests and the chosen source hash. The original source code has not been modified. `CArchivePreview` is an application-owned read-only wrapper.
