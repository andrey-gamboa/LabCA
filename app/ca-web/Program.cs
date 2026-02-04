using System.IO;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

string rootCaPath = "/opt/ca-lab/pki/root/pki/ca.crt";
string chainPath  = "/opt/ca-lab/pki/intermediate/pki/ca-chain.crt";

app.MapGet("/", () =>
{
    bool ready = File.Exists(rootCaPath) && File.Exists(chainPath);

    var html = $@"
<html>
  <head>
    <title>Lab CA Server</title>
    <style>
      body {{ font-family: Segoe UI, Arial; margin: 40px; }}
      .ok {{ color: green; }}
      .fail {{ color: red; }}
    </style>
  </head>
  <body>
    <h2>Lab CA Server</h2>
    <p>Status: <b class='{(ready ? "ok" : "fail")}'>{(ready ? "PKI READY ✅" : "NOT INITIALIZED ❌")}</b></p>

    {(ready ? @"
    <ul>
      <li><a href='/root.crt'>Download Root CA</a></li>
      <li><a href='/ca-chain.crt'>Download CA Chain</a></li>
    </ul>
    " : "<p>Run <code>init-pki.sh</code> to initialize the CA.</p>")}
  </body>
</html>";

    return Results.Content(html, "text/html");
});

app.MapGet("/root.crt", () =>
{
    if (!File.Exists(rootCaPath))
        return Results.NotFound("Root CA not found");

    return Results.File(
        rootCaPath,
        "application/x-x509-ca-cert",
        "root-ca.crt"
    );
});

app.MapGet("/ca-chain.crt", () =>
{
    if (!File.Exists(chainPath))
        return Results.NotFound("CA chain not found");

    return Results.File(
        chainPath,
        "application/x-x509-ca-cert",
        "ca-chain.crt"
    );
});

app.Run("http://127.0.0.1:5000");
