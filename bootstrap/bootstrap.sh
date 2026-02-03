#!/usr/bin/env bash
set -euo pipefail

# ---- Settings
BASE="/opt/ca-lab"
SCRIPTS_DIR="$BASE/scripts"
APP_DIR="$BASE/app/ca-web"
PUBLISH_DIR="$APP_DIR/publish"
ISSUED_DIR="$BASE/issued"

# Use UID 1000 user if exists; fallback to 'labcauser'
CA_USER="$(id -un 1000 2>/dev/null || echo labcauser)"

echo "[LabCA] Using CA_USER=$CA_USER"

# ---- Packages
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 easy-rsa zip unzip wget curl ca-certificates gnupg

# ---- Install .NET 8 SDK (Ubuntu 24.04 / noble)
wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb
rm /tmp/packages-microsoft-prod.deb
apt-get update
apt-get install -y dotnet-sdk-8.0

# ---- Create base folders
mkdir -p "$SCRIPTS_DIR" "$BASE/pki" "$ISSUED_DIR" "$BASE/app"
chown -R "$CA_USER:$CA_USER" "$BASE"

# ---- Drop PKI scripts
cat > "$SCRIPTS_DIR/init-pki.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

EASYRSA_BIN="$(command -v easyrsa || true)"
if [[ -z "$EASYRSA_BIN" && -x /usr/share/easy-rsa/easyrsa ]]; then
  EASYRSA_BIN="/usr/share/easy-rsa/easyrsa"
fi
[[ -z "$EASYRSA_BIN" ]] && echo "easyrsa not found" && exit 127

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

if [[ -f "$ROOT/pki/ca.crt" && -f "$INT/pki/ca.crt" && -f "$INT/pki/private/ca.key" ]]; then
  echo "PKI already initialized."
  exit 0
fi

mkdir -p "$ROOT" "$INT"

write_vars() {
  local dir="$1"
  : > "$dir/vars"
  printf 'set_var EASYRSA_REQ_COUNTRY    "%s"\n' "$COUNTRY" >> "$dir/vars"
  printf 'set_var EASYRSA_REQ_PROVINCE   "%s"\n' "$PROVINCE" >> "$dir/vars"
  printf 'set_var EASYRSA_REQ_CITY       "%s"\n' "$CITY" >> "$dir/vars"
  printf 'set_var EASYRSA_REQ_ORG        "%s"\n' "$ORG" >> "$dir/vars"
  printf 'set_var EASYRSA_REQ_EMAIL      "%s"\n' "$EMAIL" >> "$dir/vars"
  printf 'set_var EASYRSA_REQ_OU         "%s"\n' "$OU" >> "$dir/vars"
  printf 'set_var EASYRSA_ALGO           "ec"\n' >> "$dir/vars"
  printf 'set_var EASYRSA_DIGEST         "sha512"\n' >> "$dir/vars"
}

export EASYRSA_BATCH=1

# ROOT
cd "$ROOT"
write_vars "$ROOT"
"$EASYRSA_BIN" init-pki
EASYRSA_REQ_CN="$ROOT_CN" "$EASYRSA_BIN" build-ca nopass

# INTERMEDIATE (canonical name: ca)
cd "$INT"
write_vars "$INT"
"$EASYRSA_BIN" init-pki
EASYRSA_REQ_CN="$INT_CN" "$EASYRSA_BIN" gen-req ca nopass

# Root signs intermediate
cd "$ROOT"
"$EASYRSA_BIN" import-req "$INT/pki/reqs/ca.req" intermediate
"$EASYRSA_BIN" sign-req ca intermediate

cp "$ROOT/pki/issued/intermediate.crt" "$INT/pki/ca.crt"
cp "$ROOT/pki/ca.crt" "$INT/pki/root-ca.crt"
cat "$INT/pki/ca.crt" "$INT/pki/root-ca.crt" > "$INT/pki/ca-chain.crt"

echo "PKI initialized OK."
echo "Root CA: $ROOT/pki/ca.crt"
echo "Chain  : $INT/pki/ca-chain.crt"
EOF

cat > "$SCRIPTS_DIR/issue-cert.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

EASYRSA_BIN="$(command -v easyrsa || true)"
if [[ -z "$EASYRSA_BIN" && -x /usr/share/easy-rsa/easyrsa ]]; then
  EASYRSA_BIN="/usr/share/easy-rsa/easyrsa"
fi
[[ -z "$EASYRSA_BIN" ]] && echo "easyrsa not found" && exit 127

INT_DIR="/opt/ca-lab/pki/intermediate"
ISSUED_BASE="/opt/ca-lab/issued"

NAME="${1:?name required}"
TYPE="${2:-server}"
DAYS="${3:-365}"
SANS_RAW="${4:-}"

if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]{3,64}$ ]]; then
  echo "Invalid name"
  exit 2
fi
if [[ "$TYPE" != "server" && "$TYPE" != "client" ]]; then
  echo "Invalid type"
  exit 2
fi
if [[ ! "$DAYS" =~ ^[0-9]{1,4}$ ]] || (( DAYS < 1 || DAYS > 3650 )); then
  echo "Invalid days"
  exit 2
fi
if [[ ! -f "$INT_DIR/pki/ca.crt" || ! -f "$INT_DIR/pki/private/ca.key" ]]; then
  echo "Intermediate CA not initialized"
  exit 3
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

echo "OK"
echo "OUT_DIR=$OUT_DIR"
echo "ZIP=$ISSUED_BASE/$NAME.zip"
EOF

chmod 0755 "$SCRIPTS_DIR/init-pki.sh" "$SCRIPTS_DIR/issue-cert.sh"
chown -R "$CA_USER:$CA_USER" "$SCRIPTS_DIR"

# ---- Apache reverse proxy
cat > /etc/apache2/sites-available/000-default.conf <<'EOF'
<VirtualHost *:80>
  ServerName localhost
  ProxyPreserveHost On
  ProxyPass / http://127.0.0.1:5000/
  ProxyPassReverse / http://127.0.0.1:5000/
</VirtualHost>
EOF

a2enmod proxy proxy_http rewrite
systemctl restart apache2

# ---- Create minimal C# app
mkdir -p "$APP_DIR"
chown -R "$CA_USER:$CA_USER" "$BASE/app"

# Create project and overwrite Program.cs with our version
sudo -u "$CA_USER" -H bash -lc "dotnet new web -n ca-web -o '$APP_DIR' --force"

cat > "$APP_DIR/Program.cs" <<'EOF'
using System.Diagnostics;
using System.Text;
using Microsoft.AspNetCore.Http;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

string RootCrtPath => "/opt/ca-lab/pki/root/pki/ca.crt";
string ChainCrtPath => "/opt/ca-lab/pki/intermediate/pki/ca-chain.crt";
string InitScript => "/opt/ca-lab/scripts/init-pki.sh";
string IssueScript => "/opt/ca-lab/scripts/issue-cert.sh";
string IssuedZip(string name) => $"/opt/ca-lab/issued/{name}.zip";

bool PkiReady() =>
    File.Exists(RootCrtPath) &&
    File.Exists(ChainCrtPath) &&
    File.Exists("/opt/ca-lab/pki/intermediate/pki/private/ca.key");

static async Task<(int exitCode, string output)> Run(string file, string args)
{
    var psi = new ProcessStartInfo
    {
        FileName = file,
        Arguments = args,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false
    };
    var p = Process.Start(psi)!;
    var stdout = await p.StandardOutput.ReadToEndAsync();
    var stderr = await p.StandardError.ReadToEndAsync();
    await p.WaitForExitAsync();
    return (p.ExitCode, stdout + "\n" + stderr);
}

string Layout(string body)
{
    return $"""
    <html><body style='font-family:Segoe UI,Arial;max-width:900px;margin:40px'>
    <h2>Lab CA Server</h2>
    {body}
    <hr/>
    <p style='color:#666'>Host: {Environment.MachineName}</p>
    </body></html>
    """;
}

app.MapGet("/", () =>
{
    if (!PkiReady())
    {
        return Results.Content(Layout("""
            <p>Status: <b>NOT INITIALIZED ❌</b></p>
            <p><a href='/setup'>Go to /setup</a></p>
        """), "text/html");
    }

    return Results.Content(Layout("""
        <p>Status: <b>PKI READY ✅</b></p>
        <ul>
          <li><a href='/root.crt'>Download Root CA (root-ca.crt)</a></li>
          <li><a href='/ca-chain.crt'>Download CA Chain (intermediate+root)</a></li>
          <li><a href='/issue'>Issue a certificate</a></li>
        </ul>
    """), "text/html");
});

app.MapGet("/setup", () =>
{
    var html = """
    <h3>Initialize Root + Intermediate CA</h3>
    <form method='post'>
      <label>Root CN</label><br/><input name='rootCn' value='Lab Root CA' style='width:420px'/><br/><br/>
      <label>Intermediate CN</label><br/><input name='intCn' value='Lab Intermediate CA' style='width:420px'/><br/><br/>
      <label>Country</label><br/><input name='country' value='CR'/><br/><br/>
      <label>Province</label><br/><input name='province' value='SanJose'/><br/><br/>
      <label>City</label><br/><input name='city' value='Lab'/><br/><br/>
      <label>Org</label><br/><input name='org' value='LabCA'/><br/><br/>
      <label>OU</label><br/><input name='ou' value='IT'/><br/><br/>
      <label>Email</label><br/><input name='email' value='admin@example.local' style='width:420px'/><br/><br/>
      <button type='submit'>Initialize PKI</button>
    </form>
    <p><a href='/'>Back</a></p>
    """;
    return Results.Content(Layout(html), "text/html");
});

app.MapPost("/setup", async (HttpRequest req) =>
{
    var form = await req.ReadFormAsync();

    string rootCn = form["rootCn"];
    string intCn = form["intCn"];
    string country = form["country"];
    string province = form["province"];
    string city = form["city"];
    string org = form["org"];
    string ou = form["ou"];
    string email = form["email"];

    // Run with bash, as root (service runs as user, but app is behind Apache; keep it simple)
    var args = $"\"{InitScript}\" \"{rootCn}\" \"{intCn}\" \"{country}\" \"{province}\" \"{city}\" \"{org}\" \"{ou}\" \"{email}\"";
    var (code, output) = await Run("/bin/bash", args);

    if (code != 0)
    {
        return Results.Content(Layout($"""
          <p>Setup failed ❌</p>
          <pre style='background:#111;color:#ddd;padding:12px;white-space:pre-wrap'>{System.Net.WebUtility.HtmlEncode(output)}</pre>
          <p><a href='/setup'>Back</a></p>
        """), "text/html");
    }

    return Results.Redirect("/");
});

app.MapGet("/root.crt", () =>
{
    if (!File.Exists(RootCrtPath)) return Results.NotFound("Root CA not found.");
    return Results.File(RootCrtPath, "application/x-x509-ca-cert", "root-ca.crt");
});

app.MapGet("/ca-chain.crt", () =>
{
    if (!File.Exists(ChainCrtPath)) return Results.NotFound("CA chain not found.");
    return Results.File(ChainCrtPath, "application/x-x509-ca-cert", "ca-chain.crt");
});

app.MapGet("/issue", () =>
{
    if (!PkiReady()) return Results.Redirect("/setup");

    var html = """
    <h3>Issue Certificate</h3>
    <form method='post'>
      <label>Name (CN)</label><br/><input name='name' value='web01' style='width:220px'/><br/><br/>
      <label>Type</label><br/>
        <select name='type'>
          <option value='server' selected>server</option>
          <option value='client'>client</option>
        </select><br/><br/>
      <label>Days</label><br/><input name='days' value='365' style='width:120px'/><br/><br/>
      <label>SANs (example: DNS:web01.lab,IP:10.0.0.4)</label><br/>
      <input name='sans' value='DNS:web01.lab,IP:10.0.0.4' style='width:520px'/><br/><br/>
      <button type='submit'>Issue</button>
    </form>
    <p><a href='/'>Back</a></p>
    """;
    return Results.Content(Layout(html), "text/html");
});

app.MapPost("/issue", async (HttpRequest req) =>
{
    if (!PkiReady()) return Results.Redirect("/setup");

    var form = await req.ReadFormAsync();
    string name = form["name"];
    string type = form["type"];
    string days = form["days"];
    string sans = form["sans"];

    // Use bash script
    var args = $"\"{IssueScript}\" \"{name}\" \"{type}\" \"{days}\" \"{sans}\"";
    var (code, output) = await Run("/bin/bash", args);

    if (code != 0)
    {
        return Results.Content(Layout($"""
          <p>Issue failed ❌</p>
          <pre style='background:#111;color:#ddd;padding:12px;white-space:pre-wrap'>{System.Net.WebUtility.HtmlEncode(output)}</pre>
          <p><a href='/issue'>Back</a></p>
        """), "text/html");
    }

    var zipPath = IssuedZip(name);
    if (!File.Exists(zipPath))
    {
        return Results.Content(Layout($"""
          <p>Issued OK, but zip not found ❌</p>
          <pre style='background:#111;color:#ddd;padding:12px;white-space:pre-wrap'>{System.Net.WebUtility.HtmlEncode(output)}</pre>
          <p><a href='/issue'>Back</a></p>
        """), "text/html");
    }

    return Results.Content(Layout($"""
      <p>Issued ✅</p>
      <p><a href='/issued/{name}.zip'>Download ZIP</a></p>
      <pre style='background:#111;color:#ddd;padding:12px;white-space:pre-wrap'>{System.Net.WebUtility.HtmlEncode(output)}</pre>
      <p><a href='/issue'>Back</a></p>
    """), "text/html");
});

app.MapGet("/issued/{file}", (string file) =>
{
    var safe = file.Replace("..", "").Replace("/", "").Replace("\\", "");
    var full = $"/opt/ca-lab/issued/{safe}";
    if (!System.IO.File.Exists(full)) return Results.NotFound("Not found.");
    return Results.File(full, "application/zip", safe);
});

app.Run();
EOF

# Publish
sudo -u "$CA_USER" -H bash -lc "dotnet publish '$APP_DIR/ca-web.csproj' -c Release -o '$PUBLISH_DIR'"

# ---- systemd unit
cat > /etc/systemd/system/ca-web.service <<EOF
[Unit]
Description=CA Lab Web App
After=network.target

[Service]
WorkingDirectory=$PUBLISH_DIR
ExecStart=/usr/bin/dotnet $PUBLISH_DIR/ca-web.dll
Restart=always
User=$CA_USER
Environment=ASPNETCORE_URLS=http://127.0.0.1:5000
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ca-web

echo "[LabCA] Bootstrap complete."
echo "[LabCA] Web: http://<PublicIP>/"
echo "[LabCA] Logs: /var/log/labca-bootstrap.log"
