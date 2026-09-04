# Ruby generator overrides

`partial_model_generic.mustache` is copied from OpenAPI Generator 7.17.0's
`ruby-client/partial_model_generic.mustache`. Its only change lets nullable map
fields retain explicitly supplied `nil` values during construction. Omitted
fields stay omitted. `generation_spec.rb` exercises the generated serializer.

Compare this override with upstream when upgrading the pinned generator.
