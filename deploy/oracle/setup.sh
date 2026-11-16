#!/usr/bin/env bash
# Installs or updates the Tichu authority server on an Ubuntu VM (Oracle
# Cloud Always Free). Run as root from the directory holding the uploaded
# files; .github/workflows/deploy-authority.yml does this on every deploy.
#
#   sudo bash setup.sh <public-hostname>
#
# Expects in the current directory: authority, tichu_q_v3.safetensors,
# tichu-authority.service. Expects /etc/tichu-authority.env (secrets).
# Idempotent: safe to run on every deploy.
set -euo pipefail

HOSTNAME_PUBLIC="${1:?usage: setup.sh <public-hostname>}"
APP_DIR=/opt/tichu-authority

if [[ ! -f /etc/tichu-authority.env ]]; then
  echo "Missing /etc/tichu-authority.env" >&2
  exit 1
fi

# Caddy terminates HTTPS (automatic Let's Encrypt) and proxies to the
# authority on localhost.
if ! command -v caddy >/dev/null; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
fi

# Oracle's Ubuntu images block everything but SSH in iptables, on top of the
# cloud security list. Open 80/443 and persist the rules.
if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
  echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
fi
for port in 80 443; do
  if ! iptables -C INPUT -p tcp --dport "$port" -m state --state NEW -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 5 -p tcp --dport "$port" -m state --state NEW -j ACCEPT
  fi
done
netfilter-persistent save >/dev/null

id tichu >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin tichu

install -d -o root -g root -m 755 "$APP_DIR" "$APP_DIR/assets/bots"
install -o root -g root -m 755 authority "$APP_DIR/authority"
install -o root -g root -m 644 tichu_q_v3.safetensors "$APP_DIR/assets/bots/tichu_q_v3.safetensors"
install -o root -g root -m 644 tichu-authority.service /etc/systemd/system/tichu-authority.service
chown root:tichu /etc/tichu-authority.env
chmod 640 /etc/tichu-authority.env

cat > /etc/caddy/Caddyfile <<EOF
${HOSTNAME_PUBLIC} {
	reverse_proxy 127.0.0.1:8081
}
EOF

systemctl daemon-reload
systemctl enable --quiet tichu-authority caddy
systemctl restart tichu-authority
systemctl reload caddy || systemctl restart caddy

echo "Deployed. https://${HOSTNAME_PUBLIC}/health"
