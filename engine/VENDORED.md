# Vendored LÖVE engine

This is LÖVE 12-dev (https://github.com/love2d/love), vendored at commit
**540e681** (2026-07-05, "vulkan: fix validation errors…"), plus the Apple
dependency frameworks from love2d/love-apple-dependencies (branch main,
commit 69049d7) already installed under platform/xcode/.

Why vendored: the game ships on an unreleased engine branch; the build must be
reproducible forever from THIS repo alone, and we own small modifications
(project identity, the StoreKit bridge membership). To update the engine:
diff against upstream deliberately, never `git pull` blindly.

Our modifications to the vendored tree are marked with "BATSPILLET:" comments
or live in the game repo and are synced in by ios.sh (ios/love-ios.plist).
