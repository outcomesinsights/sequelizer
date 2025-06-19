#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

echo "Initializing firewall rules..."

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta | jq -r '.git[],.web[],.api[],.pages[]' | sort -u)
for range in $gh_ranges; do
    echo "Adding GitHub range: $range"
    ipset add allowed-domains "$range"
done

# Define allowed domains for Claude Code functionality
declare -a domains=(
    "api.anthropic.com"
    "claude.ai"
    "github.com"
    "raw.githubusercontent.com"
    "registry.npmjs.org"
    "rubygems.org"
    "index.rubygems.org"
    "api.rubygems.org"
    "bundler.rubygems.org"
    "fastly.com"
    "cloudflare.com"
    "amazonaws.com"
    "docker.io"
    "docker.com"
    "gcr.io"
    "quay.io"
)

# Resolve domains to IP addresses and add to ipset
for domain in "${domains[@]}"; do
    echo "Resolving $domain..."
    ips=$(dig +short "$domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add allowed-domains "$ip"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outbound connections to allowed IPs
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Allow outbound HTTPS (443) and HTTP (80) to allowed domains
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -m set --match-set allowed-domains dst -j ACCEPT

echo "Firewall rules configured successfully"

# Verify firewall configuration
echo "Verifying firewall configuration..."
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

# Test Claude API connectivity
if ! curl --connect-timeout 5 https://api.anthropic.com >/dev/null 2>&1; then
    echo "WARNING: Unable to reach https://api.anthropic.com - Claude Code may not work properly"
else
    echo "Claude API connectivity verified"
fi

echo "Firewall initialization completed successfully"