# Release installation

1. Context: users need a prebuilt macOS app without Xcode or a source checkout.
2. Decision: publish versioned Apple Silicon ZIP, SHA-256, and installer assets on GitHub Releases.
3. Authority: maintainers build a tested feature revision locally; GitHub credentials only publish the reviewed revision and artifacts.
4. Ownership: the existing build script owns bundling; GitHub owns distribution; the Bash installer owns validation, installation, and temporary-file cleanup.
5. Contract: each installer pins one release tag and installs one app into `~/Applications` (or an explicit directory), never replacing an existing app.
6. Bounds: explicit user invocation, two HTTPS downloads with size/time limits, one archive, no privileged operations or accumulated-history scans.
7. Trust: the repository and TLS authenticate the source; the checksum detects corrupt downloads and code-signature verification detects invalid bundles, not publisher identity.
8. Failure: unsupported hosts, network failures, invalid checksums/signatures, and existing apps fail closed; no launch or credential access occurs during installation.
9. Bootstrap: publish all assets together after tests and archive validation; missing releases fail explicitly; this first release is ad-hoc signed and unnotarized, with manual Gatekeeper approval documented.
10. Rollback: retain old app bundles, quit before restoring one, and reauthorize capture if needed; withdraw a defective release from Latest and publish a new version rather than replace versioned assets.
