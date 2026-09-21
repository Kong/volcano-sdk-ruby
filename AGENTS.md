# SDK quality

- Before pushing, run `bundle exec rake quality`. CI runs the same command on
  Ruby 3.2 and 3.4. OpenAPI generation also requires Node 22 and Java 21.
- Fix failures rather than weakening rules, excluding code, or suppressing
  findings. Never approve quality-policy changes on a human reviewer's behalf.
- Keep generated clients private. Regenerate them from the checked-in OpenAPI
  snapshot; never edit generated output by hand.
- Preserve shared behavioral scenarios and coordinate contract changes with
  `Kong/volcano-hosting` and the other SDKs.
- Keep maintainer guidance under `maintainers/`; `docs/` is published.
