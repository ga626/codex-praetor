# Codex Praetor 0.16.29-alpha

This maintenance release hardens candidate activation and host refresh handling.

- Candidate activation is idempotent for an already verified artifact.
- Deferred host refresh writes a durable pending state and verifies the exact cache generation.
- A plugin version cannot be reused for different cached content generations.
- A running Codex Desktop host is reported as awaiting host exit without a doomed cache update attempt.
- Qoder China tasks continue to use the documented `--print --output-format stream-json` transport; cancellation is controlled process cancellation rather than an unbounded worker retry.
