# Public signatures

`bundle exec rake quality:types` validates the shipped `sig/` tree with RBS and
checks callers with Steep. Those tools accept explicit `untyped` and unchecked
`...` overloads, so `spec/quality/public_signature_types_spec.rb` inspects RBS's
parsed declarations and rejects both. It covers nested method, alias, attribute,
and generic types; development signatures remain outside the shipped `sig/`.
