# Ruby generator overrides

`partial_model_generic.mustache` is copied from OpenAPI Generator 7.17.0's
`ruby-client/partial_model_generic.mustache`. Its only change lets nullable map
fields retain explicitly supplied `nil` values during construction. Omitted
fields stay omitted. `generation_spec.rb` exercises the generated serializer.

Compare this override with upstream when upgrading the pinned generator.

`partial_oneof_module.mustache` comes from the same pinned generator's
`ruby-client/partial_oneof_module.mustache`. Its three model lookups use
`Object.const_get` to resolve the private generated namespace. Direct constant
access raises inside union matching and silently discards valid nested values.
`generated_transport_model_boundaries_spec.rb` exercises scalar and nested-array
unions with the namespace private.
Nested unions also retain `false` results instead of treating them as a failed
match. The upstream template SHA256 is
`c6da53b56e16bc39bfaa2965c07c0d259837999b4a4673aa68cac2e3b571713f`.
