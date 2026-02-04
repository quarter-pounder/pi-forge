# Adblocker domain (Pi-hole + Unbound)

The adblocker domain runs Pi-hole and Unbound in a single Compose stack. Unbound gets its IP from Docker (no fixed address), and Pi-hole reaches it by service name `unbound`. That way the stack can restart or recreate containers after a reboot without "Address already in use" or manual recovery.

## If the Pi has no DNS (can't resolve github.com, Docker pull fails)

When adblocker is down or not yet up, the host can have no working DNS (e.g. resolv.conf pointed at 127.0.0.53 with nothing listening). Fix it once, then bring adblocker up:

```bash
# One-time fix so the host can resolve names (run as root or sudo)
sudo bash -c 'echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf'
# Then run the full DNS fallback script so it sticks across reboots
sudo bash ~/pi-forge/common/scripts/configure-dns-fallback.sh
# Now deploy adblocker
cd ~/pi-forge && make deploy DOMAIN=adblocker
```

After `configure-dns-fallback.sh` has been run (e.g. during `make setup-systemd-services` or manually), the host should use fallback DNS when adblocker is unavailable.

## Dependencies

- Pi-hole depends on Unbound (health check). Unbound must be up for Pi-hole to stay healthy.
- The adblocker domain is standalone; it does not depend on other domains.
