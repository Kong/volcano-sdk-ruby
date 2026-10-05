# Property tests

Property tests run 200 cases each through PropCheck and shrink failing inputs.
Each property gets its own random generator initialized from the RSpec seed.
Replay a failure with the spec path and the printed seed:

```sh
bundle exec rspec spec/volcano/storage_bucket_properties_spec.rb --seed 12345
```

Failures write the seed, original input, minimized counterexample, and assertion
to `reports/property-failures/`. CI preserves those files as artifacts. Promote
counterexamples that expose a bug into explicit regression examples when fixing it.
