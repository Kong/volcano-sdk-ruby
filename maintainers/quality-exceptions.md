# Quality exceptions

| Rule | Scope | Rationale | Evidence |
| --- | --- | --- | --- |
| Steep `Ruby::MethodDefinitionMissing` | `Volcano::Error::VolcanoError#status`, `#code`, and `#retry_after` in `lib/volcano/errors.rb` | Steep cannot infer methods created by `attr_reader`; RuboCop `Style/TrivialAccessors` requires these readers to use `attr_reader`. The three-method `@dynamic` annotation leaves their public RBS types and consumer checks active. | [Steep's documented accessor annotation](https://github.com/soutaro/steep#2-write-ruby-code); removing this annotation produces exactly three `Ruby::MethodDefinitionMissing` diagnostics under `bundle exec steep check --jobs 1`. |
