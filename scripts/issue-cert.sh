#!/usr/bin/env bash
set -Eeuo pipefail

NAME="${1:?name required}"
TYPE="${2:-server}"
DAYS="${3:-365}"
SANS_RAW="${4:-}"

LOG_DIR="/var/log/labca"
LOG_FILE="$LOG_DIR/issue-$NAME.log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

EASYRSA_BIN="$(command -v easyrsa || true)"
if [[ -z "$EASYRSA_BIN" && -x /usr/share/easy-rsa/easyrsa ]]; then
  EASYRSA_BIN="/usr/share/easy-rsa/easyrsa"
fi
[[ -z "$EASYRSA_BIN" ]] && echo "❌ easyrsa not found" && exit 127

INT_DIR="/opt/ca-lab/pki/intermediate"
ISSUED_BASE="/opt/ca-lab/issued"

if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]{3,64}$ ]]; then echo "Invalid name"; exit 2; fi
if [[ "$TYPE" != "server" && "$TYPE" != "client" ]]; then echo "Invalid type"; exit 2; fi
if [[ ! "$DAYS" =~ ^[0-9]{1,4}$ ]] || (( DAYS < 1 || DAYS > 3650 )); then echo "Invalid days"; exit 2; fi
if [[ ! -f "$INT_DIR/pki/ca.crt" || ! -f "$INT_DIR/pki/private/ca.key" ]]; then
  echo "Intermediate CA not initialized"; exit 3
fi

mkdir -p "$ISSUED_BASE"
OUT_DIR="$ISSUED_BASE/$NAME"
mkdir -p "$OUT_DIR"

cd "$INT_DIR"
export EASYRSA_BATCH=1
export EASYRSA_CERT_EXPIRE="$DAYS"

EXTRA_EXTS=""
if [[ -n "$SANS_RAW" ]]; then
  SANS="$(echo "$SANS_RAW" | tr -d ' ')"
  EXTRA_EXTS="subjectAltName=$SANS"
fi

"$EASYRSA_BIN" --vars="$INT_DIR/vars" gen-req "$NAME" nopass
if [[ -n "$EXTRA_EXTS" ]]; then
  EASYRSA_EXTRA_EXTS="$EXTRA_EXTS" "$EASYRSA_BIN" --vars="$INT_DIR/vars" sign-req "$TYPE" "$NAME"
else
  "$EASYRSA_BIN" --vars="$INT_DIR/vars" sign-req "$TYPE" "$NAME"
fi

cp "$INT_DIR/pki/private/$NAME.key" "$OUT_DIR/$NAME.key"
cp "$INT_DIR/pki/issued/$NAME.crt" "$OUT_DIR/$NAME.crt"
cp "$INT_DIR/pki/ca-chain.crt" "$OUT_DIR/ca-chain.crt"
cat "$OUT_DIR/$NAME.crt" "$OUT_DIR/ca-chain.crt" > "$OUT_DIR/fullchain.pem"

cd "$ISSUED_BASE"
zip -qr "$ISSUED_BASE/$NAME.zip" "$NAME"

# ---------- Quiet summary (THIS is what UI should show) ----------
echo "OK"
echo "OUT_DIR=$OUT_DIR"
echo "ZIP=$ISSUED_BASE/$NAME.zip"
echo "Log=$LOG_FILE"
