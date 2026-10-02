# SDK quality

- Research upstream tools before adding enforcement. Keep rules in native tool
  configuration and orchestration in standard tasks. Add custom checks only
  for requirements established tools cannot express; document that gap.
- Use judgment for pragmatic exceptions justified by verified tool limitations
  or compatibility constraints. Never grant review approval on a human's behalf.
- Keep reviewer and repository-administration credentials outside ordinary
  automation.
- Keep native unit, type, build, and package checks here. Hosting owns behavioral
  acceptance scenarios and bindings; coordinate changes with `Kong/volcano-hosting`.
- Keep maintainer guidance under `maintainers/`; `docs/` is published.
