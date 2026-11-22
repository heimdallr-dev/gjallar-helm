#!/usr/bin/env bash
# Import the gjallar realm into an EXISTING Keycloak running in Kubernetes, and
# create the users "admin" and "viewer" with random temporary passwords
# (Keycloak asks for a new one at first sign-in). Run where kubectl works.
#
#   KC_NS=keycloak KC_SVC=keycloak-http KC_PORT=8443 \
#   KC_ADMIN_SECRET=keycloak-bootstrap-admin KC_CA_SECRET=keycloak-server-tls \
#   keycloak/import-realm.sh
#
# Nothing secret is printed. The admin login comes from $KC_ADMIN_SECRET (keys
# username/password); the new users' passwords go to Secret
# gjallar/gjallar-initial-users. TLS is verified with ca.crt from
# $KC_CA_SECRET (unset = plain HTTP to the service). Idempotent: an existing
# realm or user is left as is.
set -euo pipefail
cd "$(dirname "$0")"
KC_NS=${KC_NS:-keycloak} KC_SVC=${KC_SVC:-keycloak-http} KC_PORT=${KC_PORT:-8443}
KC_ADMIN_SECRET=${KC_ADMIN_SECRET:-keycloak-bootstrap-admin} KC_CA_SECRET=${KC_CA_SECRET:-}
NS=${GJALLAR_NS:-gjallar} LOCAL=18443
umask 077
W=$(mktemp -d); PF=
trap '[ -n "$PF" ] && kill "$PF" 2>/dev/null; rm -rf "$W"' EXIT
kubectl -n "$KC_NS" port-forward "svc/$KC_SVC" "$LOCAL:$KC_PORT" >/dev/null 2>&1 & PF=$!
host="$KC_SVC.$KC_NS.svc"
if [ -n "$KC_CA_SECRET" ]; then
  kubectl -n "$KC_NS" get secret "$KC_CA_SECRET" -o jsonpath='{.data.ca\.crt}' | base64 -d > "$W/ca.crt"
  KC="https://$host:$LOCAL"; C=(curl -sS --fail-with-body --cacert "$W/ca.crt" --resolve "$host:$LOCAL:127.0.0.1")
else
  KC="http://127.0.0.1:$LOCAL"; C=(curl -sS --fail-with-body)
fi
for _ in $(seq 30); do "${C[@]}" -o /dev/null "$KC/realms/master" 2>/dev/null && break; sleep 1; done
sec() { kubectl -n "$1" get secret "$2" -o jsonpath="{.data.$3}" | base64 -d; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
T=$("${C[@]}" -d grant_type=password -d client_id=admin-cli --data-urlencode "username=$(sec "$KC_NS" "$KC_ADMIN_SECRET" username)" \
  --data-urlencode "password=$(sec "$KC_NS" "$KC_ADMIN_SECRET" password)" "$KC/realms/master/protocol/openid-connect/token" | json 'd["access_token"]')
H="Authorization: Bearer $T"
if "${C[@]}" -o /dev/null -H "$H" "$KC/admin/realms/gjallar" 2>/dev/null; then
  echo "realm gjallar: exists, left as is"
else # the file's demo users are replaced below by users with random passwords
  json 'json.dumps({k: v for k, v in d.items() if k != "users"})' < gjallar-realm.json \
    | "${C[@]}" -o /dev/null -H "$H" -H 'Content-Type: application/json' --data @- "$KC/admin/realms"
  echo "realm gjallar: imported"
fi
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" get secret gjallar-initial-users >/dev/null 2>&1 || kubectl -n "$NS" create secret generic gjallar-initial-users \
  --from-literal=admin-password="$(openssl rand -base64 18)" --from-literal=viewer-password="$(openssl rand -base64 18)" >/dev/null
for u in admin viewer; do
  if [ "$("${C[@]}" -H "$H" "$KC/admin/realms/gjallar/users?username=$u&exact=true")" = "[]" ]; then
    python3 -c 'import json,sys; print(json.dumps({"username":sys.argv[1],"enabled":True,"email":sys.argv[1]+"@gjallar.invalid","emailVerified":True,
      "firstName":sys.argv[1],"lastName":"gjallar","credentials":[{"type":"password","value":sys.argv[2],"temporary":True}]}))' \
      "$u" "$(sec "$NS" gjallar-initial-users "$u-password")" \
      | "${C[@]}" -o /dev/null -H "$H" -H 'Content-Type: application/json' --data @- "$KC/admin/realms/gjallar/users"
    echo "user $u: created (temporary password in Secret $NS/gjallar-initial-users)"
  else
    echo "user $u: exists"
  fi
  id=$("${C[@]}" -H "$H" "$KC/admin/realms/gjallar/users?username=$u&exact=true" | json 'd[0]["id"]')
  roles=gjallar-viewer; [ "$u" = admin ] && roles="gjallar-admin gjallar-viewer"
  for r in $roles; do "${C[@]}" -H "$H" "$KC/admin/realms/gjallar/roles/$r"; echo; done \
    | python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in sys.stdin if l.strip()]))' \
    | "${C[@]}" -o /dev/null -H "$H" -H 'Content-Type: application/json' --data @- "$KC/admin/realms/gjallar/users/$id/role-mappings/realm"
  echo "user $u: roles $roles"
done
