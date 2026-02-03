#!/usr/bin/env bash
set -euo pipefail

# ---------- Locate easyrsa ----------
EASYRSA_BIN="$(command -v easyrsa || true)"
if [[ -z "$EASYRSA_BIN" && -x /usr/share/easy-rsa/easyrsa ]]; then
  EASYRSA_BIN="/usr/share/easy-rsa/easyrsa"
fi
[[ -z "$EASYRSA_BIN" ]] && echo "❌ easyrsa not found" && exit 127

# ---------- Paths ----------
BASE="/opt/ca-lab/pki"
ROOT="$BASE/root"
INT="$BASE/intermediate"

# ---------- Params ----------
ROOT_CN="${1:-Lab Root CA}"
INT_CN="${2:-Lab Intermediate CA}"
COUNTRY="${3:-CR}"
PROVINCE="${4:-SanJose}"
CITY="${5:-Lab}"
ORG="${6:-LabCA}"
OU="${7:-IT}"
EMAIL="${8:-admin@example.local}"

# ---------- Idempotency ----------
if [[ -f "$ROOT/pki/ca.crt" && -f "$INT/pki/ca.crt" && -f "$INT/pki/private/ca.key" ]]; then
  echo "✅ PKI already initialized"
  exit 0
fi

mkdir -p "$ROOT" "$INT"

# ---------- Write vars ----------
write_vars() {
  local dir="$1"
  cat > "$dir/vars" <<EOF
set_var EASYRSA_REQ_COUNTRY    "$COUNTRY"
set_var EASYRSA_REQ_PROVINCE   "$PROVINCE"
set_var EASYRSA_REQ_CITY       "$CITY"
set_var EASYRSA_REQ_ORG        "$ORG"
set_var EASYRSA_REQ_EMAIL      "$EMAIL"
set_var EASYRSA_REQ_OU         "$OU"
set_var EASYRSA_ALGO           "ec"
set_var EASYRSA_DIGEST         "sha512"
EOF
}

export EASYRSA_BATCH=1

# ---------- Root CA ----------
cd "$ROOT"
write_vars "$ROOT"
"$EASYRSA_BIN" init-pki
EASYRSA_REQ_CN="$ROOT_CN" "$EASYRSA_BIN" build-ca nopass

# ---------- Intermediate CA ----------
cd "$INT"
write_vars "$INT"
"$EASYRSA_BIN" init-pki
EASYRSA_REQ_CN="$INT_CN" "$EASYRSA_BIN" gen-req ca nopass

# ---------- Sign intermediate ----------
cd "$ROOT"
"$EASYRSA_BIN" import-req "$INT/pki/reqs/ca.req" intermediate
"$EASYRSA_BIN" sign-req ca intermediate

# ---------- Build chain ----------
cp "$ROOT/pki/issued/intermediate.crt" "$INT/pki/ca.crt"
cp "$ROOT/pki/ca.crt" "$INT/pki/root-ca.crt"
cat "$INT/pki/ca.crt" "$INT/pki/root-ca.crt" > "$INT/pki/ca-chain.crt"

echo "✅ PKI initialized successfully"
echo "Root CA: $ROOT/pki/ca.crt"
echo "Chain  : $INT/pki/ca-chain.crt"

