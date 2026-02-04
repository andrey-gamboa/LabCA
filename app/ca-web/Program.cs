using System.Diagnostics;
using System.Text;
using System.Text.Encodings.Web;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

/* =======================
   Paths / config
======================= */
string RootCrt     = "/opt/ca-lab/pki/root/pki/ca.crt";
string ChainCrt    = "/opt/ca-lab/pki/intermediate/pki/ca-chain.crt";
string InitScript  = "/opt/ca-lab/scripts/init-pki.sh";
string IssueScript = "/opt/ca-lab/scripts/issue-cert.sh";
string IssuedBase  = "/opt/ca-lab/issued";

/* =======================
   Helpers
======================= */
bool PkiReady() =>
    File.Exists(RootCrt) && File.Exists(ChainCrt);

static string H(string s) =>
    HtmlEncoder.Default.Encode(s ?? "");

static bool IsSafeName(string s) =>
    s.Length is >= 3 and <= 64 &&
    s.All(ch => char.IsLetterOrDigit(ch) || "._-".Contains(ch));

static bool IsSafeText(string s) =>
    s.Length is >= 1 and <= 64 &&
    s.All(ch => char.IsLetterOrDigit(ch) || " .-_".Contains(ch));

static ProcessStartInfo Script(string path, params string[] args)
{
    var psi = new ProcessStartInfo
    {
        FileName = "/usr/bin/sudo",
        RedirectStandardOutput = true,
        RedirectStandardError = true
    };
    psi.ArgumentList.Add("/bin/bash");
    psi.ArgumentList.Add(path);
    foreach (var a in args) psi.ArgumentList.Add(a);
    return psi;
}

/* =======================
   Home
======================= */
app.MapGet("/", () =>
{
    var sb = new StringBuilder();
    sb.AppendLine("<html><body style='font-family:Segoe UI,Arial'>");
    sb.AppendLine("<h2>Lab CA Server</h2>");
    sb.AppendLine($"<p>Status: <b>{(PkiReady() ? "READY ✅" : "NOT INITIALIZED ❌")}</b></p>");

    if (!PkiReady())
    {
        sb.AppendLine("<p><a href='/setup'>Initialize PKI</a></p>");
    }
    else
    {
        sb.AppendLine("<ul>");
        sb.AppendLine("<li><a href='/root.crt'>Download Root CA</a></li>");
        sb.AppendLine("<li><a href='/ca-chain.crt'>Download CA Chain</a></li>");
        sb.AppendLine("<li><a href='/cert/new'>Issue Certificate</a></li>");
        sb.AppendLine("<li><a href='/cert/issued'>Issued Certificates</a></li>");
        sb.AppendLine("</ul>");
    }

    sb.AppendLine("</body></html>");
    return Results.Content(sb.ToString(), "text/html");
});

/* =======================
   Setup (GET)
======================= */
app.MapGet("/setup", () =>
{
    if (PkiReady())
        return Results.Content(
            "<html><body><h3>PKI already initialized ✅</h3><a href='/'>Home</a></body></html>",
            "text/html");

    return Results.Content(@"
<html><body style='font-family:Segoe UI,Arial; max-width:820px'>
<h2>Initialize PKI</h2>

<form method='post'>
<label>Root CA CN</label><br>
<input name='rootCn' value='Lab Root CA' style='width:420px'><br><br>

<label>Intermediate CA CN</label><br>
<input name='intCn' value='Lab Intermediate CA' style='width:420px'><br><br>

<fieldset style='padding:12px'>
<legend>Org Info</legend>
Country <input name='country' value='CR'><br>
Province <input name='province' value='SanJose'><br>
City <input name='city' value='Lab'><br>
Org <input name='org' value='LabCA'><br>
OU <input name='ou' value='IT'><br>
Email <input name='email' value='admin@example.local'><br>
</fieldset><br>

<button type='submit'>Create PKI</button>
</form>

<p><a href='/'>Home</a></p>
</body></html>", "text/html");
});

/* =======================
   Setup (POST)
======================= */
app.MapPost("/setup", async (HttpRequest req) =>
{
    if (PkiReady())
        return Results.BadRequest("PKI already initialized");

    var f = await req.ReadFormAsync();

    string rootCn = f["rootCn"];
    string intCn  = f["intCn"];

    if (!IsSafeText(rootCn) || !IsSafeText(intCn))
        return Results.BadRequest("Invalid CN");

    var psi = Script(
        InitScript,
        rootCn, intCn,
        f["country"], f["province"], f["city"],
        f["org"], f["ou"], f["email"]
    );

    using var p = Process.Start(psi)!;
    var stdout = await p.StandardOutput.ReadToEndAsync();
    var stderr = await p.StandardError.ReadToEndAsync();
    await p.WaitForExitAsync();

    if (p.ExitCode != 0)
    {
        return Results.Content($@"
<html><body>
<h3>Setup failed ❌</h3>
<pre>{H(stderr)}</pre>
<a href='/setup'>Back</a>
</body></html>", "text/html");
    }

    return Results.Content(@"
<html><body>
<h3>PKI initialized successfully ✅</h3>
<ul>
<li><a href='/root.crt'>Download Root CA</a></li>
<li><a href='/ca-chain.crt'>Download CA Chain</a></li>
<li><a href='/cert/new'>Issue Certificate</a></li>
</ul>
<a href='/'>Home</a>
</body></html>", "text/html");
});

/* =======================
   Downloads
======================= */
app.MapGet("/root.crt", () =>
    File.Exists(RootCrt)
        ? Results.File(RootCrt, "application/x-x509-ca-cert", "root-ca.crt")
        : Results.NotFound());

app.MapGet("/ca-chain.crt", () =>
    File.Exists(ChainCrt)
        ? Results.File(ChainCrt, "application/x-x509-ca-cert", "ca-chain.crt")
        : Results.NotFound());

/* =======================
   Issue cert (GET)
======================= */
app.MapGet("/cert/new", () =>
{
    if (!PkiReady())
        return Results.Content("<h3>PKI not initialized ❌</h3><a href='/setup'>Setup</a>", "text/html");

    return Results.Content(@"
<html><body style='font-family:Segoe UI,Arial; max-width:820px'>
<h2>Issue Certificate</h2>

<form method='post'>
Name <input name='name' value='web01'><br><br>
Type <select name='type'><option>server</option><option>client</option></select><br><br>
Days <input name='days' value='365'><br><br>
SANs <input name='sans' value='DNS:web01.lab,IP:10.0.0.4' style='width:520px'><br><br>

<button type='submit'>Generate</button>
</form>

<p><a href='/'>Home</a></p>
</body></html>", "text/html");
});

/* =======================
   Issue cert (POST)
======================= */
app.MapPost("/cert/new", async (HttpRequest req) =>
{
    var f = await req.ReadFormAsync();

    string name = f["name"];
    string type = f["type"];
    string days = f["days"];
    string sans = f["sans"];

    if (!IsSafeName(name))
        return Results.BadRequest("Invalid name");

    if (!int.TryParse(days, out int d) || d < 1 || d > 3650)
        return Results.BadRequest("Invalid days");

    var psi = Script(IssueScript, name, type, d.ToString(), sans);

    using var p = Process.Start(psi)!;
    var stdout = await p.StandardOutput.ReadToEndAsync();
    var stderr = await p.StandardError.ReadToEndAsync();
    await p.WaitForExitAsync();

    if (p.ExitCode != 0)
    {
        return Results.Content($@"
<html><body>
<h3>Issue failed ❌</h3>
<pre>{H(stderr)}</pre>
<a href='/cert/new'>Back</a>
</body></html>", "text/html");
    }

    return Results.Content($@"
<html><body>
<h3>Certificate issued successfully ✅</h3>
<p><a href='/cert/download/{H(name)}'>Download ZIP</a></p>
<p><a href='/cert/issued'>Issued certificates</a></p>
<p><a href='/'>Home</a></p>
</body></html>", "text/html");
});

/* =======================
   Issued list
======================= */
app.MapGet("/cert/issued", () =>
{
    Directory.CreateDirectory(IssuedBase);

    var rows = Directory.GetFiles(IssuedBase, "*.zip")
        .Select(f => Path.GetFileNameWithoutExtension(f))
        .OrderByDescending(x => x)
        .Select(n => $"<tr><td>{H(n)}</td><td><a href='/cert/download/{H(n)}'>Download</a></td></tr>");

    return Results.Content($@"
<html><body>
<h2>Issued Certificates</h2>
<table border='1' cellpadding='6'>
<tr><th>Name</th><th>Download</th></tr>
{string.Join("\n", rows)}
</table>
<p><a href='/'>Home</a></p>
</body></html>", "text/html");
});

/* =======================
   Download
======================= */
app.MapGet("/cert/download/{name}", (string name) =>
{
    if (!IsSafeName(name)) return Results.BadRequest();

    var zip = Path.Combine(IssuedBase, $"{name}.zip");
    return File.Exists(zip)
        ? Results.File(zip, "application/zip", $"{name}.zip")
        : Results.NotFound();
});

app.Run();
