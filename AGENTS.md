# SDK quality

- Research upstream tools before adding enforcement. Keep rules in native tool
  configuration and orchestration in standard tasks. Add custom checks only
  for requirements established tools cannot express; document that gap.
- Use judgment for pragmatic exceptions justified by verified tool limitations
  or compatibility constraints. Never grant review approval on a human's behalf.
- Keep reviewer and repository-administration credentials outside ordinary
  automation.
- Preserve shared behavioral scenarios and coordinate contract changes with
  `Kong/volcano-hosting` and the other SDKs.
- Keep maintainer guidance under `maintainers/`; `docs/` is published.
