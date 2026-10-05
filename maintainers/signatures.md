# Public signatures

`bundle exec rake quality:types` validates the shipped `sig/` tree with RBS and
checks callers with Steep. Those tools accept explicit `untyped`, unchecked
`...` overloads, and `(?)` parameter lists, so
`spec/quality/public_signature_types_spec.rb` rejects them in RBS's parsed
declarations. It covers nested method, proc, block, alias, attribute, and generic
types; development signatures remain outside the shipped `sig/`.

The RSpec package check builds a gem, compares its public signature inventory
with `sig/`, and checks valid and invalid callers with Steep in a temporary
project that reads only signatures extracted from that gem. The separate
isolated install smoke test confirms the gem runs without development type tools.
