#!/usr/bin/env bash
# End-to-end smoke test through the Ingress.
#   ./scripts/smoke-test.sh [base-url] [host-header]
# Local kind cluster : ./scripts/smoke-test.sh http://localhost:8080 streamingapp.local
# EKS / hosts entry  : ./scripts/smoke-test.sh http://<ingress-hostname>
set -uo pipefail
BASE="${1:-http://streamingapp.local}"
HOST="${2:-}"
HDR=()
[ -n "$HOST" ] && HDR=(-H "Host: $HOST")
FAIL=0
EMAIL="smoke$(date +%s)@example.com"

get()  { curl -s -m 10 "${HDR[@]}" "$BASE$1"; }
post() { curl -s -m 10 "${HDR[@]}" -X POST "$BASE$1" -H 'Content-Type: application/json' -d "$2"; }
check() { # name, expected substring, actual
  if echo "$3" | grep -q "$2"; then echo "PASS  $1"; else echo "FAIL  $1 -> $(echo "$3" | head -c 200)"; FAIL=1; fi
}

check "frontend serves React SPA (/)"         '<div id="root">'             "$(get /)"
check "streaming catalogue (/api/streaming)"  '"success":true'              "$(get /api/streaming/videos)"
check "register (/api/auth/register)"         '"success":true'              "$(post /api/auth/register "{\"name\":\"Smoke Test\",\"email\":\"$EMAIL\",\"password\":\"Test@1234\"}")"
LOGIN="$(post /api/auth/login "{\"email\":\"$EMAIL\",\"password\":\"Test@1234\"}")"
check "login returns a JWT (/api/auth/login)" '"token"'                     "$LOGIN"
check "chat service routed (/api/chat)"       'Authentication required'     "$(get /api/chat/history/test)"
check "admin service routed (/api/admin)"     'Authorization token missing' "$(get /api/admin/videos)"
check "socket.io handshake (/socket.io)"      '"sid"'                       "$(get '/socket.io/?EIO=4&transport=polling')"

[ $FAIL -eq 0 ] && echo "ALL SMOKE TESTS PASSED" || echo "SOME SMOKE TESTS FAILED"
exit $FAIL
