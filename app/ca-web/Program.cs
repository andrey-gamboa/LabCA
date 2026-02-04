using System.Diagnostics;
using System.Text;
using System.Text.Encodings.Web;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

string RootCrt = "/opt/ca-lab/pki/root/pki/ca.crt";
string ChainCrt = "/opt/ca-lab/pki/intermediate/pki/ca-chain.crt";
string InitScript = "/opt/ca-lab/scripts/init-pki.sh";
string IssueScript = "/opt/ca-lab/scripts/issue-cert.sh";
string IssuedBase = "/opt/ca-lab/issued";

bool PkiReady() => File.Exists(RootCrt) && File.Exists(ChainCrt);
static string H(string s) => HtmlEncoder.Default.Encode(s ?? "");

static bool IsSafeName(string s) =>
    s.Length is >= 3 and <= 64 && s.All(ch => char.IsLetterOrDigit(ch) || "._-".Contains(ch));

static bool IsSafeText(string s) =>
    s.Length is >= 1 and <= 64 && s.All(ch => char.IsLetterOrDigit(ch) || " .-_".Contains(ch));

app.MapGet("/", () =>
{
    var sb = new StringBuilder();
    sb.AppendLine("<html><body style='font-family:Segoe UI,Arial'>");
    sb.AppendLine("<h2>Lab CA Server</h2>");
    sb.AppendLine($"<p>Status: <b>{(PkiReady() ? "READY" : "NOT INITIALIZED")}</b></p>");

    if (!PkiReady())
    {
        sb.AppendLine("<p><a href='/setup'>Go to /setup</a></p>");
    }
    else
    {
        sb.AppendLine("<ul>");
        sb.AppendLine("<li><a href='/root.crt'>Download Root CA (root-ca.crt)</a></li>");
        sb.AppendLine("<li><a href='/ca-chain.crt'>Download CA Chain (intermediate+root)</a></li>");
        sb.AppendLine("<li><a href='/cert/new'>Issue a new certificate</a></li>");
        sb.AppendLine("</ul>");
    }

    sb.AppendLine("</body></html>");
    return Results.Content(sb.ToString(), "text/html");
});

app.MapGet("/setup", () =>
{
    if (PkiReady())
        return Results.Content("<html><body><h3>PKI already initialized</h3><a href='/'>Home</a></body></html>", "text/html");

    var setupTokenEnabled = !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("SETUP_TOKEN"));

    var html = $@"
<html><body style='font-family:Segoe UI,Arial; max-width:820px'>
<h2>Initialize PKI (Root + Intermediate)</h2>
<p><b>Lab mode:</b> Root/Intermediate are created with <code>nopass</code> (no passphrase) for automation.</p>

<form method='post' action='/setup'>
  {(setupTokenEnabled ? "<label>Setup Token</label><br><input name='token' type='password' style='width:420px' /><br><br>" : "")}

  <label>Root CA Common Name</label><br>
  <input name='rootCn' value='Lab Root CA' style='width:420px' /><br><br>

  <label>Intermediate CA Common Name</label><br>
  <input name='intCn' value='Lab Intermediate CA' style='width:420px' /><br><br>

  <fieldset style='padding:12px'>
    <legend>Org info (optional)</legend>
    <label>Country</label><br><input name='country' value='CR' /><br>
    <label>Province/State</label><br><input name='province' value='SanJose' style='width:420px' /><br>
    <label>City</label><br><input name='city' value='Lab' style='width:420px' /><br>
    <label>Org</label><br><input name='org' value='LabCA' style='width:420px' /><br>
    <label>OU</label><br><input name='ou' value='IT' style='width:420px' /><br>
    <label>Email</label><br><input name='email' value='admin@example.local' style='width:420px' /><br>
  </fieldset>
  <br>
  <button type='submit'>Create PKI</button>
</form>

<p><a href='/'>Home</a></p>
</body></html>";
    return Results.Content(html, "text/html");
});

app.MapPost("/setup", async (HttpRequest req) =>
{
    if (PkiReady())
        return Results.BadRequest("PKI already initialized.");

    var form = await req.ReadFormAsync();

    var expectedToken = Environment.GetEnvironmentVariable("SETUP_TOKEN");
    if (!string.IsNullOrWhiteSpace(expectedToken))
    {
        var provided = form["token"].ToString();
        if (provided != expectedToken)
            return Results.Unauthorized();
    }

    string rootCn = form["rootCn"].ToString().Trim();
    string intCn = form["intCn"].ToString().Trim();

    if (!IsSafeText(rootCn) || !IsSafeText(intCn))
        return Results.BadRequest("Invalid CN. Use letters/numbers/space/.-_ and 1-64 chars.");

    string country = form["country"].ToString().Trim();
    string province = form["province"].ToString().Trim();
    string city = form["city"].ToString().Trim();
    string org = form["org"].ToString().Trim();
    string ou = form["ou"].ToString().Trim();
    string email = form["email"].ToString().Trim();

    var psi = new ProcessStartInfo
    {
        FileName = "/bin/bash",
        RedirectStandardOutput = true,
        RedirectStandardError = true
    };
    psi.ArgumentList.Add(InitScript);
    psi.ArgumentList.Add(rootCn);
    psi.ArgumentList.Add(intCn);
    psi.ArgumentList.Add(country);
    psi.ArgumentList.Add(province);
    psi.ArgumentList.Add(city);
    psi.ArgumentList.Add(org);
    psi.ArgumentList.Add(ou);
    psi.ArgumentList.Add(email);

    using var p = Process.Start(psi)!;
    var stdout = await p.StandardOutput.ReadToEndAsync();
    var stderr = await p.StandardError.ReadToEndAsync();
    await p.WaitForExitAsync();

    if (p.ExitCode != 0)
    {
        var msg = $"<html><body><h3>Setup failed</h3><pre>{H(stdout)}\n{H(stderr)}</pre><a href='/setup'>Back</a></body></html>";
        return Results.Content(msg, "text/html");
    }

    var okMsg = $@"
<html><body style='font-family:Segoe UI,Arial'>
<h3>PKI initialized</h3>
<ul>
  <li><a href='/root.crt'>Download Root CA</a></li>
  <li><a href='/ca-chain.crt'>Download Chain</a></li>
  <li><a href='/cert/new'>Issue a certificate</a></li>
</ul>
<pre>{H(stdout)}</pre>
<p><a href='/'>Home</a></p>
</body></html>";
    return Results.Content(okMsg, "text/html");
});

app.MapGet("/root.crt", () =>
{
    if (!File.Exists(RootCrt)) return Results.NotFound("Root CA not found.");
    return Results.File(RootCrt, "application/x-x509-ca-cert", "root-ca.crt");
});

app.MapGet("/ca-chain.crt", () =>
{
    if (!File.Exists(ChainCrt)) return Results.NotFound("CA chain not found.");
    return Results.File(ChainCrt, "application/x-x509-ca-cert", "ca-chain.crt");
});

app.MapGet("/cert/new", () =>
{
    if (!PkiReady())
        return Results.Content("<html><body><h3>PKI not initialized ❌</h3><a href='/setup'>Go to /setup</a></body></html>", "text/html");

    var html = @"
<html><body style='font-family:Segoe UI,Arial; max-width:820px'>
<h2>Issue a certificate</h2>
<form method='post' action='/cert/new'>
  <label>Name (file-safe; 3-64 chars: A-Z a-z 0-9 . _ -)</label><br>
  <input name='name' value='web01' style='width:420px' /><br><br>

  <label>Type</label><br>
  <select name='type'>
    <option value='server' selected>server</option>
    <option value='client'>client</option>
  </select><br><br>

  <label>Validity (days)</label><br>
  <input name='days' value='365' /><br><br>

  <label>SANs (comma-separated)</label><br>
  <input name='sans' value='DNS:web01.lab,IP:10.0.0.4' style='width:620px' /><br>
  <small>Example: DNS:web01.lab,IP:10.0.0.4</small><br><br>

  <button type='submit'>Generate + Download ZIP</button>
</form>
<p><a href='/'>Home</a></p>
</body></html>";
    return Results.Content(html, "text/html");
});

app.MapPost("/cert/new", async (HttpRequest req) =>
{
    if (!PkiReady())
        return Results.BadRequest("PKI not initialized.");

    var form = await req.ReadFormAsync();
    string name = form["name"].ToString().Trim();
    string type = form["type"].ToString().Trim();
    string days = form["days"].ToString().Trim();
    string sans = form["sans"].ToString().Trim();

    if (!IsSafeName(name))
        return Results.BadRequest("Invalid name. Use 3-64 chars: A-Z a-z 0-9 . _ -");

    if (type != "server" && type != "client")
        return Results.BadRequest("Invalid type. Use server or client.");

    if (!int.TryParse(days, out var daysInt) || daysInt < 1 || daysInt > 3650)
        return Results.BadRequest("Invalid days. Use 1..3650");

    // Run issue script
    var psi = new ProcessStartInfo
    {
        FileName = "/bin/bash",
        RedirectStandardOutput = true,
        RedirectStandardError = true
    };
    psi.ArgumentList.Add(IssueScript);
    psi.ArgumentList.Add(name);
    psi.ArgumentList.Add(type);
    psi.ArgumentList.Add(daysInt.ToString());
    psi.ArgumentList.Add(sans);

    using var p = Process.Start(psi)!;
    var stdout = await p.StandardOutput.ReadToEndAsync();
    var stderr = await p.StandardError.ReadToEndAsync();
    await p.WaitForExitAsync();

    if (p.ExitCode != 0)
    {
        var msg = $"<html><body><h3>Issue failed ❌</h3><pre>{H(stdout)}\n{H(stderr)}</pre><a href='/cert/new'>Back</a></body></html>";
        return Results.Content(msg, "text/html");
    }

    // Redirect to download
    return Results.Redirect($"/cert/download/{Uri.EscapeDataString(name)}");
});

app.MapGet("/cert/download/{name}", (string name) =>
{
    if (!IsSafeName(name)) return Results.BadRequest("Invalid name.");

    var zipPath = Path.Combine(IssuedBase, $"{name}", $"{name}.zip");
    // Note: script writes /opt/ca-lab/issued/<name>.zip (one level up)
    var zipPathAlt = Path.Combine(IssuedBase, $"{name}.zip");

    if (File.Exists(zipPathAlt))
        return Results.File(zipPathAlt, "application/zip", $"{name}.zip");

    if (File.Exists(zipPath))
        return Results.File(zipPath, "application/zip", $"{name}.zip");

    return Results.NotFound("ZIP not found. Generate the cert first.");
});

app.Run();
