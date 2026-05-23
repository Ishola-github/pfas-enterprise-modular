# ONE COMMAND REPRODUCIBILITY

## Canonical Tag
serum-v2.0.0-temporal

## Docker Mode A (Preferred)

Run from clean clone:

```bash
docker compose up --build
```

## Expected PASS Conditions

- Governance CI checks passing
- Docker/Linux reproducibility passing
- Schema validation passing
- Smoke API verification passing
- Canonical SHA-256 hashes matching
- Frozen release verification successful

## Reviewer Workflow

1. Clone repository
2. Checkout canonical tag:

```bash
git checkout serum-v2.0.0-temporal
```

3. Run Docker reproducibility workflow
4. Compare hashes against canonical release
5. Complete reviewer attestation template
6. Return signed attestation

## Expected Runtime

~30–90 minutes depending on environment setup.
