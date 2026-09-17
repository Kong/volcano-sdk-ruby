# Staged contract scenarios

These copies are pending additions to hosting's canonical SDK contract. They do
not count as active coverage and ordinary contract runs do not execute them.
Keep each file byte-identical to its coordinated hosting change and add its
language binding before merging the SDK change.

Hosting activates a scenario only after every SDK has the matching copy. Once
that hosting change reaches main, move the copy into `features/contract` and
update the native copy checks. Keep active copies unchanged until activation;
hosting's current main must remain compatible throughout the rollout.
