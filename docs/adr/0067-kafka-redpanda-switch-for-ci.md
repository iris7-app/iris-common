# ADR-0067 — Kafka CI image switch (bitnamilegacy → redpanda)

**Status** : Accepted (shipped 2026-05-10)
* Decision date : 2026-05-10
* Deciders : @Beennnn
* Tags : `ci`, `kafka`, `services`

## Context

`iris-service-python` integration-tests required a kafka broker as a CI
service. The original config used `bitnamilegacy/kafka:3.7-debian-12`
(KRaft mode, no Zookeeper). After 5 attempts to make this work :

1. Default 30s service health check — kafka KRaft bootstrap > 30s, timeout
2. Local runner network_per_build=true — DNS resolves, kafka still
   unreachable in time
3. Local runner privileged=true — same
4. Local runner wait_for_services_timeout=120 — kafka still unreachable
5. SaaS Linux runner (saas-linux-medium-amd64) — default 30s timeout,
   no override available

Common bottleneck across all 5 attempts : kafka KRaft bootstrap is too
slow to satisfy a 30s TCP-dial health check.

## Decision

Switch the kafka CI service to [redpanda](https://redpanda.com) :
wire-protocol-compatible Kafka broker written in C++ that boots in
~3-5s.

`.gitlab-ci/test.yml` config :

```yaml
services:
  - name: redpandadata/redpanda:v24.2.10
    alias: kafka
    command:
      - redpanda
      - start
      - --kafka-addr=PLAINTEXT://0.0.0.0:9092
      - --advertise-kafka-addr=PLAINTEXT://kafka:9092
      - --smp=1
      - --memory=512M
      - --reserve-memory=0M
      - --node-id=0
      - --check=false
      - --mode=dev-container
```

`--mode=dev-container` enables relaxed defaults (no replication, no
disk-flush) appropriate for ephemeral CI.

The `aiokafka` Python client connects via `kafka:9092` unchanged —
redpanda speaks the kafka protocol transparently.

## Alternatives considered

1. **Custom kafka image with prefetched state**.
   - ❌ Maintenance burden + Docker build pipeline complexity.
2. **Skip kafka tests in CI, keep only postgres**.
   - ❌ Loses gate on kafka client behaviour ; can't catch aiokafka
     compatibility regressions.
3. **GitHub Actions only** (drop GitLab CI for integration-tests).
   - ❌ Loses single-source-of-truth on GitLab ; doubles CI maintenance.
4. **Embed kafka start-up script with extended sleep**.
   - ❌ Hacky, breaks health check semantics, hard to debug when it fails.

## Trade-offs

- ✅ **Boot time** : redpanda 3-5s vs kafka 30-45s.
- ✅ **Wire compat** : aiokafka client unchanged.
- ✅ **No app code change** : producers + consumers continue to talk port 9092.
- ⚠️ **Production parity** : prod uses Apache Kafka. CI now uses redpanda.
  Wire protocol is identical but edge-case behaviours can differ (rare —
  redpanda is widely Kafka-API tested). Compensating control : load + smoke
  tests run against real kafka clusters in staging.
- ⚠️ **Cluster scenarios** : multi-broker / partition rebalance / failover
  scenarios are not testable on a single redpanda node in dev-container
  mode. These remain manual against real kafka clusters in staging.
- ⚠️ **License** : redpanda Community Edition (BSL 1.1, free for non-
  competitive use). iris-7 is a portfolio project, not a kafka-as-a-service
  competitor → compliant.

## Reverting

If a redpanda-specific behaviour ever bites, revert by switching back to
`bitnamilegacy/kafka:3.7-debian-12` with the original KAFKA_CFG_* env vars
(see audit doc) AND :
- Set `wait_for_services_timeout = 180` on the consumer runner config
  (works on local runners only)
- Accept that on SaaS this approach is unworkable — pick another path
  (Approach B from
  [docs/audit/runner-dind-migration-2026-05-09.md](https://gitlab.com/iris-7/iris-service-python/-/blob/main/docs/audit/runner-dind-migration-2026-05-09.md))

## Status post-shipping

- Shipped 2026-05-10 in `iris-service-python` (!77).
- First live run : main pipeline #2514037064 success — postgres + redpanda
  service containers both reachable in ~5s.
- GitHub Actions side : kept bitnamilegacy/kafka with extended healthchecks
  (20 retries × 10s = 200s) because GH Actions `services:` doesn't accept
  arbitrary `command:` overrides.

## Related ADRs / docs

- [docs/audit/kafka-ci-redpanda-switch-2026-05-10.md](https://gitlab.com/iris-7/iris-service-python/-/blob/main/docs/audit/kafka-ci-redpanda-switch-2026-05-10.md) — detailed
  investigation log with reproductions.
- [ADR-0066](0066-auto-merge-dev-to-main-template.md) — CI template pattern (context for why we keep adding shared CI infra).
