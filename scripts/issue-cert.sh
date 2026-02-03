
#!/usr/bin/env bash
set -euo pipefail

# ---------- Locate easyrsa ----------
EASYRSA_BIN="$(command -v easyrsa || true)"
if [[ -z "$EASYRSA_BIN" && -x /usr/share/easy-rsa/easyrsa ]]; then
  EASYRSA_BIN="/usr/share/easy-rsa/easyrsa"
fi
[[ -z "$EASYRSA_BIN" ]] && echo "❌ easyrsa not found" && exit 127

INT_DIR="/opt/ca-lab/pki/intermediate"
ISSUED_BASE="/opt/ca-lab/issued"

# ---------- Args ----------
NAME="${1:?certificate name required}"
TYPE="${2:-server}"     # server | client
DAYS="${3:-365}"
SANS_RAW="${4:-}"

# ---------- Validation ----------
[[ "$NAME" =~ ^[A-Za-z0-9._-]{3,64}$ ]] || { echo "❌ Invalid name"; exit 2; }
[[ "$TYPE" == "server" || "$TYPE" == "client" ]] || { echo "❌ Invalid type"; exit 2; }
[[ "$DAYS" =~ ^[0-9]{1,4}$ ]] || { echo "❌ Invalid days"; exit 2; }

[[ -f "$INT_DIR/pki/ca.crt" && -f "$INT_DIR/pki/private/ca.key" ]] || {
  echo "❌ Intermediate CA not initialized"
  exit 3
}

mkdir -p "$ISSUED_BASE/$NAME"
OUT_DIR="$ISSUED_BASE/$NAME"

# ---------- Issue ----------
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
  EASYRSA_EXTRA_EXTS="$EXTRA_EXTS" \
    "$EASYRSA_BIN" --vars="$INT_DIR/vars" sign-req "$TYPE" "$NAME"
else
  "$EASYRSA_BIN" --vars="$INT_DIR/vars" sign-req "$TYPE" "$NAME"
fi

# ---------- Output ----------
cp "$INT_DIR/pki/private/$NAME.key" "$OUT_DIR/$NAME.key"
cp "$INT_DIR/pki/issued/$NAME.crt" "$OUT_DIR/$NAME.crt"
cp "$INT_DIR/pki/ca-chain.crt" "$OUT_DIR/ca-chain.crt"
cat "$OUT_DIR/$NAME.crt" "$OUT_DIR/ca-chain.crt" > "$OUT_DIR/fullchain.pem"

cd "$ISSUED_BASE"
zip -qr "$NAME.zip" "$NAME"

echo "✅ Certificate issued"
echo "ZIP: $ISSUED_BASE/$NAME.zip"
