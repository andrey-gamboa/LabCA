#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="/var/log/labca"
LOG_FILE="$LOG_DIR/init-pki.log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------- Locate easyrsa ----------
EASYRSA_BIN="$(command -v easyrsa || true)"
if [[ -z "$EASYRSA_BIN" && -x /usr/share/easy-rsa/easyrsa ]]; then
  EASYRSA_BIN="/usr/share/easy-rsa/easyrsa"
fi
[[ -z "$EASYRSA_BIN" ]] && echo "❌ easyrsa not found" && exit 127

BASE="/opt/ca-lab/pki"
ROOT="$BASE/root"
INT="$BASE/intermediate"

ROOT_CN="${1:-Lab Root CA}"
INT_CN="${2:-Lab Intermediate CA}"
COUNTRY="${3:-CR}"
PROVINCE="${4:-SanJose}"
CITY="${5:-Lab}"
ORG="${6:-LabCA}"
OU="${7:-IT}"
EMAIL="${8:-admin@example.local}"

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

# Idempotent check
if [[ -f "$ROOT/pki/ca.crt" && -f "$INT/pki/ca.crt" && -f "$INT/pki/private/ca.key" ]]; then
  echo "PKI already initialized."
else
  mkdir -p "$ROOT" "$INT"

  # Root
  cd "$ROOT"
  write_vars "$ROOT"
  "$EASYRSA_BIN" init-pki
  EASYRSA_REQ_CN="$ROOT_CN" "$EASYRSA_BIN" build-ca nopass

  # Intermediate
  cd "$INT"
  write_vars "$INT"
  "$EASYRSA_BIN" init-pki
  EASYRSA_REQ_CN="$INT_CN" "$EASYRSA_BIN" gen-req ca nopass

  # Root signs intermediate
  cd "$ROOT"
  "$EASYRSA_BIN" import-req "$INT/pki/reqs/ca.req" intermediate
  "$EASYRSA_BIN" sign-req ca intermediate

  # Build chain
  cp "$ROOT/pki/issued/intermediate.crt" "$INT/pki/ca.crt"
  cp "$ROOT/pki/ca.crt" "$INT/pki/root-ca.crt"
  cat "$INT/pki/ca.crt" "$INT/pki/root-ca.crt" > "$INT/pki/ca-chain.crt"
fi

# Ensure intermediate CA DB exists (Easy-RSA 3.1+)
mkdir -p "$INT/pki"/{issued,certs,private,reqs,certs_by_serial,certs_by_subject}
[[ -f "$INT/pki/index.txt" ]] || : > "$INT/pki/index.txt"
[[ -f "$INT/pki/index.txt.attr" ]] || : > "$INT/pki/index.txt.attr"
[[ -f "$INT/pki/serial" ]] || echo 1000 > "$INT/pki/serial"
[[ -f "$INT/pki/crlnumber" ]] || echo 1000 > "$INT/pki/crlnumber"
chmod 700 "$INT/pki/private" || true

# ---------- Quiet summary (THIS is what the UI should show) ----------
echo "OK"
echo "Root CA: $ROOT/pki/ca.crt"
echo "Chain  : $INT/pki/ca-chain.crt"
echo "Log    : $LOG_FILE"
