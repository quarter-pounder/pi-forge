# Monitoring Domain

The monitoring domain deploys Prometheus, Alertmanager, Grafana, Loki, node-exporter, cAdvisor, and Grafana Alloy to observe the Forgejo stack, CI/CD runners, and the Raspberry Pi host. Alloy tails Docker container log files with labels supplied by `container-name-exporter`.

## Contract

- **Lifecycle**: `make deploy DOMAIN=monitoring`
- **State**: `/srv/monitoring/{prometheus,alertmanager,grafana,loki}`
- **Networks**:
  - `monitoring-network` – local bridge for exporters and core services
  - `forgejo-network` – shared with Forgejo, PostgreSQL, and Woodpecker
- **Outputs**:
  - Prometheus on `PORT_MONITORING_PROMETHEUS`
  - Alertmanager on `PORT_MONITORING_ALERTMANAGER`
  - Grafana on `PORT_MONITORING_GRAFANA`
  - Loki on `PORT_MONITORING_LOKI`
  - Alloy HTTP server on `PORT_MONITORING_ALLOY`

---

## Services

### Core Services
- **Prometheus**: Metrics collection and alerting
- **Alertmanager**: Alert routing and inhibition
- **Grafana**: Dashboards and visualization
- **Loki**: Log aggregation
- **Alloy**: Log collection from Docker containers
- **node-exporter**: Host level CPU, disk, and memory metrics
- **cAdvisor**: Container metrics (CPU, memory, network, filesystem)

### Helper Services
- **alert-suppression-exporter**: Generates metrics for alert suppression when services are manually downed
- **container-name-exporter**: Maps Docker container IDs to names (`container_name_info`) and refreshes `container_log_targets.json` for Alloy log tailing

---

## Prometheus Targets

Prometheus discovers services over the shared Docker bridge. The scrape jobs include:

- `forgejo:3000/metrics` (bearer token: `FORGEJO_METRICS_TOKEN`)
- `woodpecker:9000/metrics`
- `node-exporter:9100`
- `cadvisor:8080`
- `prometheus:9090`
- External runner node-exporter (if `EXTERNAL_RUNNER_METRICS_IP` is set)

---

## Grafana Dashboards

Grafana is provisioned with stable datasource UIDs (`prometheus`, `loki`).
Dashboards load from:
`generated/monitoring/dashboards/`

### Services Overview

Includes:

- **Summary**: Attention required panel, service status overview
- **Core Domains**: Forgejo, Prometheus, Loki CPU and memory usage
- **Resource Usage**: CPU and memory per service
- **Adblocker**: Pi-hole and Unbound container availability and status
- **Pi System**: CPU temperature, core voltage, throttle flags
- **Logs**: Error logs and all logs from Loki

### Runners Overview

Includes:

- **Currently Online Runners**: Count of active runners
- **Status per runner**: Offline / Idle / Active
  - Woodpecker Runner
  - Forgejo Actions Runner
  - GitHub Actions Runner
  - External Runner (if configured)
- **CPU usage** (cores and %)
- **Memory usage** (bytes and %)
- **Network I/O**

All panel queries rely directly on cAdvisor’s `name` label for reliability.

---

## Container Metrics

cAdvisor exposes container metrics with a `name` label matching the Docker container name.

Container metrics include:
- CPU usage (`container_cpu_usage_seconds_total`)
- Memory usage (`container_memory_usage_bytes`)
- Network I/O (`container_network_receive_bytes_total`, `container_network_transmit_bytes_total`)
- Filesystem usage

The `container-name-exporter` service maintains a mapping of container IDs to names (`container_name_info` metric) for reference, but dashboard queries primarily use the `name` label from cadvisor directly.

---

## Log collection (Alloy / Loki)

`container-name-exporter` polls the Docker API every 60 seconds and writes:

- `container_names.prom` — Prometheus textfile metrics for ID-to-name mapping
- `container_log_targets.json` — Alloy targets: `__path__`, `container`, `container_name`, `service`, `stack` (from compose labels when present)

Alloy mounts the textfile directory read-only, decodes the JSON with `encoding.from_json`, and passes targets to `loki.source.file`. The docker log pipeline parses only the on-disk JSON fields (`log`, `stream`, `time`); compose metadata comes from discovery labels, not from log file contents.

Grafana Loki derived fields match the `container_name` label for cross-navigation to container metrics.

---

## Host Exporters

### Pi Telemetry Script

The host cron job collects Raspberry Pi hardware metrics using `vcgencmd` and writes them to node-exporter’s textfile directory:

- `pi_cpu_temperature_celsius`
- `pi_core_voltage_volts`
- `pi_throttle_flags` (undervoltage, throttled, etc.)

The script is located at `scripts/host/pi-telemetry.sh` and should be run via cron on the host (not in a container) to access `vcgencmd`:

```bash
sudo mkdir -p /srv/monitoring/node-exporter/textfile
sudo chmod 755 /srv/monitoring/node-exporter/textfile

sudo cp scripts/host/pi-telemetry.sh /usr/local/bin/pi-telemetry
sudo chmod +x /usr/local/bin/pi-telemetry

cat <<'EOF' | sudo tee /etc/cron.d/pi-telemetry
* * * * * root /usr/local/bin/pi-telemetry >/tmp/pi-telemetry.log 2>&1
EOF
```

The script automatically discovers `vcgencmd` in common locations (`/usr/bin`, `/opt/vc/bin`) and handles missing commands by emitting `NaN` values.

---

## Alert Suppression

When a domain is intentionally brought down with:

```
make down DOMAIN=<name>
```

a suppression marker is created under:

```
/srv/monitoring/alert-suppression/
```

`alert-suppression-exporter` exposes:

```
alert_suppression_enabled{name="<service>"} 1
```

Alertmanager uses these metrics to suppress targeted alerts—primarily for runners—to avoid false positives.

Supported suppression targets:

- `woodpecker`
- `woodpecker-runner`
- `forgejo-actions-runner`
- `github-actions-runner`

---

## Alerts

Defined in `prometheus-alerts.yml`.

### Core alert families:

- **ContainerDown** — for all non-runner containers
- **RunnerContainerDown** — with alert-suppression support
- **HighCPUUsage** — sustained CPU load
- **HighMemoryUsage** — memory pressure
- **PiTemperature** — warning at 80°C, critical at 85°C
- **PiThrottling** — undervoltage or active throttling
- **PiVoltage** — core voltage below threshold

Alertmanager routes to email and/or webhook receivers as configured.

---

## DNS Note

Prometheus resolves container names through Pi-hole running on the host.
If Pi-hole is down, targets like `woodpecker` or `forgejo` may fail DNS resolution and appear as DOWN.
Keep Pi-hole up or ensure fallback DNS exists.

---

## TLS Termination

Grafana runs HTTP internally. External HTTPS is provided by Cloudflare Tunnel (or another reverse proxy).
`GF_SERVER_ROOT_URL` is templated based on `DOMAIN`.

---

## cAdvisor Memory Metrics

Memory metrics require cgroup memory support.
Ensure the kernel command line does **not** contain:

```
cgroup_disable=memory
```

Check with:

```bash
cat /proc/cmdline
```

If memory metrics show 0MB or missing, check `domains/monitoring/CADVISOR_MEMORY_FIX.md`.

---

## Current Status

- All monitoring services operational
- Dashboards fully populated (metrics + logs)
- Alloy → Loki log pipeline healthy
- Pi telemetry reporting correctly
- Prometheus scraping all targets successfully
- Runner dashboards accurately show Offline / Idle / Active
- Alert suppression functioning as intended
