# Configure Android networking for the Amar Hisab API on the local LAN.
# Run from the mobile directory after the Android platform folder exists:
#   .\scripts\configure-android-api.ps1

$ErrorActionPreference = 'Stop'
$manifest = Join-Path $PSScriptRoot '..\android\app\src\main\AndroidManifest.xml'
$manifest = [System.IO.Path]::GetFullPath($manifest)

if (-not (Test-Path -LiteralPath $manifest)) {
  throw "AndroidManifest.xml was not found at: $manifest. From the mobile folder, run: flutter create --project-name amar_hisab_mobile --platforms android ."
}

[xml]$xml = Get-Content -LiteralPath $manifest -Raw
$androidNs = 'http://schemas.android.com/apk/res/android'
$manifestNode = $xml.DocumentElement
$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace('android', $androidNs)

$internet = $xml.SelectSingleNode("/manifest/uses-permission[@android:name='android.permission.INTERNET']", $ns)
if ($null -eq $internet) {
  $internet = $xml.CreateElement('uses-permission')
  $internet.SetAttribute('name', $androidNs, 'android.permission.INTERNET')
  $manifestNode.PrependChild($internet) | Out-Null
}

$app = $xml.SelectSingleNode('/manifest/application')
if ($null -eq $app) { throw 'AndroidManifest.xml does not contain an application element.' }
$app.SetAttribute('usesCleartextTraffic', $androidNs, 'true')

$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.Encoding = New-Object System.Text.UTF8Encoding($false)
$writer = [System.Xml.XmlWriter]::Create($manifest, $settings)
try { $xml.Save($writer) } finally { $writer.Dispose() }

Write-Host 'Android INTERNET permission and local HTTP API access are configured.' -ForegroundColor Green
Write-Host 'Note: cleartext HTTP is intended only for local LAN testing; use HTTPS for production.'
