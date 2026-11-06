#!/usr/bin/bash
# PeplowPC OS idle network audit. Run on an installed system, logged in, with no apps open.
# Records every DNS name looked up and every outbound connection for N seconds,
# so we can check the claim "nothing phones home" instead of just making it.
#   sudo tools/audit-network.sh 300
# Output: audit-<date>/hostnames.txt, connections.txt, summary.txt
set -euo pipefail

DURATION="${1:-300}"
[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }

OUT="audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "Auditing for ${DURATION}s into ${OUT}/ (leave the computer alone)"

# DNS: every name the system resolves (needs systemd 255+).
resolvectl monitor >"$OUT/resolvectl-monitor.log" 2>&1 &
mon=$!

# Connections: sample established/opening outbound sockets every second.
end=$((SECONDS + DURATION))
while ((SECONDS < end)); do
    ss -tunpH state established state syn-sent 2>/dev/null |
        awk '{print $5, $6, $7}' >>"$OUT/connections.raw"
    sleep 1
done

kill "$mon" 2>/dev/null || true
wait "$mon" 2>/dev/null || true

grep -oE '(IN|A|AAAA|HTTPS|SVCB) [^ ]+' "$OUT/resolvectl-monitor.log" 2>/dev/null |
    awk '{print $2}' | sed 's/\.$//' | sort -u >"$OUT/hostnames.txt" || true
sort -u "$OUT/connections.raw" >"$OUT/connections.txt" 2>/dev/null || true

{
    echo "PeplowPC OS network audit, $(date --iso-8601=seconds), ${DURATION}s idle"
    echo "Image: $(jq -r '.version' /usr/share/peplowpc/image-info.json 2>/dev/null || echo unknown)"
    echo
    echo "Hostnames looked up:"
    sed 's/^/  /' "$OUT/hostnames.txt"
    echo
    echo "Distinct remote endpoints (address:port  process):"
    awk '{print $2, $3}' "$OUT/connections.txt" | sort -u | sed 's/^/  /'
    echo
    echo "Compare against docs/SECURITY-BASELINE.md, 'Expected outbound connections'."
} | tee "$OUT/summary.txt"
