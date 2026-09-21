---
title: Installed-package acceptance tests
description: Build and publish the locked consumer project used by Hosting.
---

Run `bash scripts/build-acceptance.sh <package-file> <output-directory>` after
building the SDK. The command creates a standalone consumer, installs the exact
package with the language package manager, checks package loading and the public
quickstart, and exports `sdk-acceptance.tar.gz` without runtime source or SDK bytes.
The bundle contains the existing contract bindings and a native dependency lock.

Hosting authenticates the bundle and customer-registry package, restores that
package at the filename recorded in `acceptance.json`, then performs a frozen
install. Ruby first runs `bash scripts/install.sh <gem>` to unpack the verified gem
at the locked local path, then runs `bundle install` with `BUNDLE_FROZEN=true`. Build candidate bundles
with the same command before publishing; package and bundle must come from the
same source commit. Never modify imports or lockfile text in the consumer.
