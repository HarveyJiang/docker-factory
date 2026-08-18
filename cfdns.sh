#!/usr/bin/env bash
#
# cfdns.sh - Cloudflare DNS record manager
#
# Reads the API token from ${HOME}/.config/.cloudflare/api-token
# (persistent volume, survives container upgrades). The token is created by
# YOU in the Cloudflare Dashboard (My Profile > API Tokens > Create Token):
#   Permissions: Zone > Zone > Edit  +  Zone > DNS > Edit
#   Zone: 2020224.xyz
#
# Usage:
#   cfdns.sh zones                                   # list zones (read only)
#   cfdns.sh list                                    # list DNS records
#   cfdns.sh add <name> <type> <content> [ttl]       # e.g. add blog A 1.2.3.4 120
#   cfdns.sh update <id> <name> <type> <content> [ttl]
#   cfdns.sh delete <id>
set -euo pipefail

TOKEN_FILE="${CLOUDFLARE_TOKEN_FILE:-${HOME}/.config/.cloudflare/api-token}"
ZONE_NAME="${CLOUDFLARE_ZONE:-2020224.xyz}"
API="https://api.cloudflare.com/client/v4"

if [ ! -f "${TOKEN_FILE}" ]; then
  echo "error: no token file at ${TOKEN_FILE}" >&2
  echo "create it with your Cloudflare API token (Zone:Zone Edit + Zone:DNS Edit)" >&2
  exit 1
fi
TOKEN="$(tr -d '\r\n' < "${TOKEN_FILE}")"

if [ "${TOKEN}" = "YOUR_CLOUDFLARE_API_TOKEN_HERE" ]; then
  echo "error: token file still contains the placeholder." >&2
  echo "overwrite it:  ${TOKEN_FILE}" >&2
  exit 1
fi

curl() { command curl -fsS -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" "$@"; }

zone_id() {
  curl "${API}/zones?name=${ZONE_NAME}" | jq -r '.result[0].id'
}

case "${1:-}" in
  zones)
    curl "${API}/zones" | jq '.result[] | {name, id, status}'
    ;;
  list)
    zid="$(zone_id)"
    curl "${API}/zones/${zid}/dns_records?per_page=100" \
      | jq -r '.result[] | "\(.id)\t\(.type)\t\(.name)\t\(.content)\tTTL:\(.ttl)"'
    ;;
  add)
    [ $# -ge 4 ] || { echo "usage: cfdns.sh add <name> <type> <content> [ttl]" >&2; exit 1; }
    zid="$(zone_id)"
    ttl="${5:-120}"
    curl -X POST "${API}/zones/${zid}/dns_records" \
      -d "$(jq -n --arg n "$2" --arg t "$3" --arg c "$4" --argjson ttl "$ttl" \
             '{type:$t, name:$n, content:$c, ttl:$ttl, proxied:false}')" \
      | jq -r '"ok \(.result.id) \(.result.name) -> \(.result.content)"'
    ;;
  update)
    [ $# -ge 5 ] || { echo "usage: cfdns.sh update <id> <name> <type> <content> [ttl]" >&2; exit 1; }
    zid="$(zone_id)"
    ttl="${6:-120}"
    curl -X PUT "${API}/zones/${zid}/dns_records/$2" \
      -d "$(jq -n --arg n "$3" --arg t "$4" --arg c "$5" --argjson ttl "$ttl" \
             '{type:$t, name:$n, content:$c, ttl:$ttl, proxied:false}')" \
      | jq -r '"ok \(.result.id)"'
    ;;
  delete)
    [ $# -ge 2 ] || { echo "usage: cfdns.sh delete <id>" >&2; exit 1; }
    zid="$(zone_id)"
    curl -X DELETE "${API}/zones/${zid}/dns_records/$2" | jq -r '"deleted \(.result.id)"'
    ;;
  *)
    echo "usage: cfdns.sh {zones|list|add|update|delete}" >&2
    exit 1
    ;;
esac