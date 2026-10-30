$ErrorActionPreference = "Stop"

$manifestPath = Join-Path $PSScriptRoot "..\android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifestPath)) {
    throw "AndroidManifest.xml not found. Run 'flutter create --project-name amar_hisab_mobile --platforms android .' from the mobile folder first."
}

[xml]$manifest = Get-Content -Path $manifestPath -Raw
$application = $manifest.manifest.application
if ($null -eq $application) {
    throw "AndroidManifest.xml does not contain an application element."
}

$application.SetAttribute("label", "Amar Hisab")
$manifest.Save($manifestPath)
Write-Host "Android launcher name set to: Amar Hisab"
