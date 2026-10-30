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

$androidNamespace = "http://schemas.android.com/apk/res/android"
$application.SetAttribute("label", $androidNamespace, "Amar Hisab")

# Remove an accidental non-namespaced label; Android reads android:label.
if ($application.HasAttribute("label")) {
    $application.RemoveAttribute("label")
}

$manifest.Save($manifestPath)

# Verify the actual Android launcher label after saving.
[xml]$verifiedManifest = Get-Content -Path $manifestPath -Raw
$actualLabel = $verifiedManifest.manifest.application.GetAttribute("label", $androidNamespace)
if ($actualLabel -ne "Amar Hisab") {
    throw "Failed to set Android launcher label. Current android:label: '$actualLabel'"
}

Write-Host "Android launcher name set to: $actualLabel"
