# The Story Behind This Home Server

## Why built it?

It all started with a genuine question when I came across RHEL EC2 hosted GitLab servers working as a member of the infra team: does it really take thousands of dollars to host GitLab?

Licensing, enterprise OS, oversized instance flavors, storage premiums—layers of cost stacked on top of layers of inertia.  The kind of setup that makes you wonder if the wasted budget could’ve solved world hunger several times over. The punchline? They weren’t using CI. They didn't even write docs.

So I decided to tame the beast on my own Raspberry Pi because... Why not? I happen to use CI anyway.

In case you're wondering, yes, it can pull it off. You can check the `legacy` branch if you're curious about the old setup scripts. I moved on from it because it can no longer handle the complexity as I add new stuff.

After enough iterations, frustrations, and rebuilds, this stack grew into what it is now: a domain-driven home server architecture that actually behaves.

![The said Pi in its full glory](https://github.com/quarter-pounder/pi-forge/blob/main/docs/images/pi5.png)

---

## Why stepped away from GitLab CE?

At some point the heavy Omnibus stack turned into a swamp.

Puma, the application server, demanded tuning that assumes x86. Gitaly running like a separate microservice cluster. Is GitLab CE's internal nginx bindind the port anoter service trying to use? Did they change the config convention about exposing metrics to external monitoring? All of it glued together inside the Omnibus package with expectations designed for a VM with multiple vCPUs, definitely not for a single node setup.

Fumbling knee-deep in Puma configs, Sidekiq queue tuning guides, I swapped to Forgejo because it makes sense. It's a Gitea fork. Lightweight, fast, sane defaults... And you can swap between Forgejo Actions and GitHub Actions with minimal efforts.

---

## Why bother with another layer to set config?

I despise config drift. Even on something as tiny as a Pi, the moment you run more than a couple of services, reality starts to drift out of alignment.
Docker configs here, env files there, random flags forgotten until the next rebuild... Hold on a second, which port did I set for that service again?

So here I am, we have Helm at home.

I built my own config-registry layer because I want the Pi to behave like a miniature cloud environment: predictable, boring, rebuildable.

---

## Monitoring

This isn’t a data center, but it’s still a living system. Things break. Temperatures spike. Runners misbehave. It deserves a monitoring stack as much as every system does. And hey, Prometheus and Grafana are free to use.

Below are some screenshots of the dashboard.

![Grafana Dashboard Screenshot](https://github.com/quarter-pounder/pi-forge/blob/main/docs/images/dashboard-domain-1.png)

![Grafana Dashboard Screenshot](https://github.com/quarter-pounder/pi-forge/blob/main/docs/images/dashboard-domain-2.png)

![Grafana Dashboard Screenshot](https://github.com/quarter-pounder/pi-forge/blob/main/docs/images/dashboard-domain-3.png)

![Grafana Dashboard Screenshot](https://github.com/quarter-pounder/pi-forge/blob/main/docs/images/dashboard-domain-4.png)

![Grafana Dashboard Screenshot](https://github.com/quarter-pounder/pi-forge/blob/main/docs/images/dashboard-domain-5.png)

![Runner Dashboard](https://github.com/quarter-pounder/pi-forge/blob/main/docs/images/dashboard-runners.png)

---

## Hard lessons learned

Here are a some notes I took as I built this repo. They are for future me to read. You might want to skip them because they're very lengthy.

1. Firmware has opinions

NVMe migration worked on paper, but the Pi EEPROM still preferred the SD card. Correct scripts don’t matter when firmware disagrees. Sometimes the fix is manual, not clever.

2. Bash will betray you

A recursive sudo loop in 01-preflight.sh produced actual SIGSEGV crashes. Helper function name clashes caused infinite recursion. Shell scripts need strict structure or they eat themselves.

3. Environment variables must be centralized

Scripts running under `sudo` silently dropped `.env` values. Only after consolidating `load_env_layers` did all services agree on the same configuration. Scattered env loading guarantees drift.

4. Linux distributions can’t agree on anything

sshd.service doesn’t exist on some Ubuntu builds. Falling back to ssh.service avoided pointless blockers. Assumptions about service names are traps.

5. Not every failure is in logs

Router-level client isolation made SSH refuse connections for reasons the Pi couldn’t see.

6. Permissions always matter

.vault_pass failed because it was executable or root-owned. Fixing ownership and setting chmod 600 was mandatory. Anything involving secrets breaks if permissions are wrong.

7. Upstreams drift too

Forgejo mailer flags changed, default values broke startup, and SMTP_FROM needed proper formatting. Templates must enforce sane defaults because upstreams can drift too.

8. Dependencies must be explicit

Forgejo starting before Postgres caused DNS failures and crashes. Compose doesn’t guess intent. If the order matters, declare it.

9. Internal vs external URLs are not interchangeable

Forgejo Actions runner pointed at the external URL and hit a reverse proxy instead of the container. Internal services must talk over internal addresses.

10. Names matter

Prometheus scraped node-exporter, but the real container was monitoring-node-exporter. One alias fixed an entire dashboard. Observability breaks easily when naming drifts.

11. Hardware limitations leak through

cAdvisor showed 0 MB memory usage because the Pi’s kernel lacked CONFIG_CGROUP_MEMORY. Fixing it required patching and recompiling DTBs. Sometimes one must face the hardware directly.

12. Defaults are not your friend

Alertmanager’s default receiver pointed to 127.0.0.1:0, causing endless connection-refused spam. Removing meaningless defaults cleaned up the noise.

13. Backups must be deterministic

make backup silently broke because /bin/sh rejected source. Using Bash explicitly, loading envs up front, and defining .pgpass rules turned backups from “guesswork” into a predictable operation.

14. Cloud and local backups have different purposes

Cloud storage is for essentials; local storage is for everything. A declarative backup.yml separated these concerns and controlled storage cost without losing coverage.


15. Reliability is built from scars, not designs

Every architectural layer—bootstrap, config-registry, domains, monitoring—exists because something broke repeatedly until the pattern became obvious. Stability is an outcome, not a starting point.
