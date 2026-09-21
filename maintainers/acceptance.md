---
title: Installed-package acceptance tests
description: Build and publish the locked consumer project used by Hosting.
---

Run `bash scripts/build-acceptance.sh <package-file> <output-directory>` after
building the SDK. The command creates a standalone consumer and native dependency
lock without installing or executing newly resolved dependencies. It exports
`sdk-acceptance.tar.gz` with the existing contract bindings, without SDK runtime
source or package bytes.

CI uploads the package and bundle before running
`bash scripts/test-acceptance.sh <package-file> <bundle-file>` in a separate job.
That job checks frozen installation, package loading, and the public quickstart.
Signing and publishing download the original immutable artifact IDs after those
checks pass; dependencies cannot modify the originals.

Hosting authenticates the bundle and customer-registry package, restores that
package at the filename recorded in `acceptance.json`, then performs a frozen
install. Ruby first runs `bash scripts/install.sh <gem>` to unpack the verified gem
at the locked local path, then runs `bundle install` with `BUNDLE_FROZEN=true`. Build candidate bundles
with the same command before publishing; package and bundle must come from the
same source commit. Never modify imports or lockfile text in the consumer.
