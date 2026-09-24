# Public signatures

`bundle exec rake quality:types` validates the shipped `sig/` tree with RBS and
checks callers with Steep. Those tools accept explicit `untyped` and unchecked
`...` overloads, so `spec/quality/public_signature_types_spec.rb` inspects RBS's
parsed declarations and rejects both. It covers nested method, alias, attribute,
and generic types; development signatures remain outside the shipped `sig/`.

The positive examples in `tests/types/` are checked by the normal Steep target.
`tests/invalid_types/public_consumer.rb` is checked in an isolated negative target
by `spec/quality/volcano_invalid_consumer_types_spec.rb`. Wrong argument types and
an undeclared method must produce Steep diagnostics; the invalid fixture never
enters the normal consumer target or the built gem.
