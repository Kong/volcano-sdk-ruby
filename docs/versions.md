---
title: Ruby SDK versions
description: Pin a tested SDK version, check runtime compatibility, upgrade safely, and restore a previous application dependency set.
---

Pin the SDK version your application has tested. For example:

```ruby
gem "volcano-sdk", "= 0.10.1"
```

Add this line to your Gemfile, then run `bundle install`.

These are example versions, not a moving latest-version reference.
Commit `Gemfile` and `Gemfile.lock`. Install in Bundler frozen mode in CI and deployment so an unexpected dependency change fails.

## Runtime and compatibility

Use Ruby 3.2 or later. Native CI tests Ruby 3.2 and 3.4; it does not test every intervening interpreter release. REST methods are synchronous, while realtime uses an asynchronous task lifecycle.

The gem is currently on the 0.x release line. Treat a minor-version update as potentially incompatible and read its release notes before upgrading.
JavaScript, Python and Ruby releases have independent version numbers; matching numbers are not a compatibility requirement.
Ruby raises typed exceptions; JavaScript keeps its result-envelope API.
Follow your language's public facade and examples rather than importing generated transport classes.

The docs describe the current SDK source. Confirm a method is included in your installed version by checking its [release notes](https://github.com/Kong/volcano-sdk-ruby/releases) and [changelog](https://github.com/Kong/volcano-sdk-ruby/blob/main/CHANGELOG.md).
Server-dependent features also need the corresponding Volcano API behavior; installing a newer SDK does not deploy that behavior.

## Upgrade an application

1. Read the release notes between your installed version and the intended version, including breaking changes and runtime requirements.
2. Update the dependency in a branch and review the resolved lockfile changes.
3. Run the [documented quickstart](./README.md) with a disposable test project, then run the application tests for the features you use.
4. Deploy the tested application and dependency lock together. Retain the previous tested application revision and lock.

A successful package import proves installation, not compatibility with every deployed API feature.

## Restore a previous version

Restore the previously tested application revision and its dependency lock together, then install from that lock in a clean environment.
Run the same quickstart and application tests before redeploying it.
Do not select an arbitrary older SDK version or downgrade only the top-level dependency while retaining a different transitive dependency tree.

Restoring application packages does not revert server configuration, schema changes, stored data or completed operations.
Check those dependencies before rolling back an application that changed them.

## Report a compatibility problem

Open an [SDK issue](https://github.com/Kong/volcano-sdk-ruby/issues) with the installed SDK version, runtime version, affected method, expected result and a minimal reproduction.
Include a sanitized error category and status when available.
Remove keys, tokens, passwords and private response bodies.

For suspected vulnerabilities, including authentication or authorization regressions, follow [Kong’s vulnerability reporting process](https://konghq.com/compliance/vuln-disclosure) and email vulnerability@konghq.com. Do not post security reproductions in public issues, pull requests or discussions.
