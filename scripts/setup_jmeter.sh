#!/bin/bash
# setup_jmeter.sh
# Sets up JMeter + BZT environment for lua-resty-kafka-lab
# Run on JMeter server

set -e

# ==========================================
# Default values
# ==========================================
DOMAIN="resty-kafka.loadtest.rnd"
OPENRESTY_IP=""

# ==========================================
# Parse arguments
# ==========================================
while [ "$#" -gt 0 ]; do
    case "$1" in
        --openresty-server-private-ip) OPENRESTY_IP="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

# ==========================================
# Validate required parameters
# ==========================================
if [ -z "$OPENRESTY_IP" ]; then
    echo "ERROR: --openresty-server-private-ip is required"
    echo "Usage: ./setup_jmeter.sh --openresty-server-private-ip 10.0.1.1"
    exit 1
fi

echo "======================================="
echo "lua-resty-kafka-lab JMeter Setup"
echo "======================================="
echo "OpenResty IP: $OPENRESTY_IP"
echo "Domain:       $DOMAIN"
echo "======================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
JMETER_DIR_IN_REPO="$REPO_DIR/jmeter"

# ==========================================
# Update system
# ==========================================
echo "Updating system..."
apt-get update && apt-get upgrade -y

# ==========================================
# Install base dependencies
# ==========================================
echo "Installing base dependencies..."
apt-get install -y \
    git \
    curl \
    wget \
    python3-venv \
    openjdk-17-jre-headless

# ==========================================
# Install BZT in virtualenv
# ==========================================
BZT_VENV="/opt/bzt-venv"
if [ ! -d "$BZT_VENV" ]; then
    echo "Creating BZT virtualenv..."
    python3 -m venv $BZT_VENV
    echo "Installing BZT..."
    $BZT_VENV/bin/pip install bzt
    echo "BZT installed at: $BZT_VENV"
else
    echo "BZT virtualenv already exists at: $BZT_VENV"
fi

# ==========================================
# Add BZT to PATH
# ==========================================
if ! grep -q "bzt-venv/bin" ~/.bashrc; then
    echo "export PATH=\$PATH:$BZT_VENV/bin" >> ~/.bashrc
fi

# ==========================================
# System tuning
# ==========================================
echo "Tuning system for load testing..."

# Increase open files limit
if ! grep -q "nofile 65535" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
fi

# Apply ulimit for current session
ulimit -n 65535

# Network tuning
if ! grep -q "ip_local_port_range" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf << 'EOF'
# TCP tuning for load testing
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
fi

# Apply sysctl settings
sysctl -p

# ==========================================
# Copy BZT configs
# ==========================================
echo "Copying BZT configs..."
mkdir -p /opt/bzt-test/payloads
cp -r "$JMETER_DIR_IN_REPO/bzt/"* /opt/bzt-test/

# ==========================================
# Generate payload files
# ==========================================
echo "Generating payload files..."
python3 -c "print('x' * 1024)" > /opt/bzt-test/payloads/payload_1kb.txt
python3 -c "print('x' * 10240)" > /opt/bzt-test/payloads/payload_10kb.txt
python3 -c "print('x' * 102400)" > /opt/bzt-test/payloads/payload_100kb.txt

# ==========================================
# Replace domain placeholder in config.yml
# ==========================================
echo "Configuring domain..."
sed -i "s|DOMAIN_NAME|$DOMAIN|g" /opt/bzt-test/config.yml

# ==========================================
# Add domain to /etc/hosts
# ==========================================
echo "Adding domain to /etc/hosts..."
if grep -q "$DOMAIN" /etc/hosts; then
    sed -i "/$DOMAIN/d" /etc/hosts
fi
echo "$OPENRESTY_IP $DOMAIN" >> /etc/hosts

echo ""
echo "======================================="
echo "JMeter setup complete!"
echo "======================================="
echo ""
echo "NOTE: Activate PATH changes first:"
echo "  source ~/.bashrc"
echo ""
echo "Run tests from /opt/bzt-test directory:"
echo ""
echo "  cd /opt/bzt-test"
echo ""
echo "  # Async test (recommended: 200 concurrency)"
echo "  /opt/bzt-venv/bin/bzt config.yml loadtest-async.yml -o settings.env.CONCURRENCY=200"
echo ""
echo "  # Sync test (recommended: 100 concurrency)"
echo "  /opt/bzt-venv/bin/bzt config.yml loadtest-sync.yml -o settings.env.CONCURRENCY=100"
echo ""
echo "  # Payload size tests"
echo "  /opt/bzt-venv/bin/bzt config.yml loadtest-sync-1kb.yml -o settings.env.CONCURRENCY=100"
echo "  /opt/bzt-venv/bin/bzt config.yml loadtest-sync-10kb.yml -o settings.env.CONCURRENCY=100"
echo "  /opt/bzt-venv/bin/bzt config.yml loadtest-sync-100kb.yml -o settings.env.CONCURRENCY=100"
echo "======================================="

