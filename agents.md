# Agent instructions

This repository is a rootless Podman Quadlet deployment. A container or
workload change is incomplete until it has real Podman E2E coverage.

When adding or changing a container or workload:

1. Add the container to the correct workload in `manifests/applications.json`
   and keep its systemd target in sync.
2. Add or update the container's entry in `tests/e2e-readiness.json`. Use a
   native Quadlet `HealthCmd=` where possible; otherwise define a TCP probe or
   explicitly document why running-state validation is the only available
   check.
3. Add or update any test-only fixture needed for host hardware, credentials,
   external services, or seeded data. Fixtures must still run through Podman.
4. Run the focused E2E test for the changed container or workload:

   ```bash
   ./bin/e2e --container CONTAINER_NAME
   ./bin/e2e --workload WORKLOAD_NAME
   ```

5. Run the full E2E suite before declaring the work complete:

   ```bash
   ./bin/e2e
   ```

Do not replace E2E with mocked `podman` or `systemctl` commands. Do not hide a
failed, unhealthy, or unavailable container by skipping it. The full run must
start and keep every declared container running successfully.
