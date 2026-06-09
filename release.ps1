# release.ps1 — build APK release e sobe pro GCS
# Uso: .\release.ps1
# Requer: flutter, gcloud autenticado com acesso ao projeto maps-route-495614

$ErrorActionPreference = "Stop"

$pubspec = Get-Content pubspec.yaml | Where-Object { $_ -match "^version:" }
if ($pubspec -match "version:\s*(.+)") {
    $version = $Matches[1].Trim()
} else {
    Write-Error "Nao foi possivel ler versao do pubspec.yaml"
    exit 1
}

Write-Host "Buildando v$version..." -ForegroundColor Cyan

flutter build apk --release --no-tree-shake-icons `
    "--dart-define-from-file=dart_defines.json"

$apk    = "build\app\outputs\flutter-apk\app-release.apk"
$dest   = "gs://truck-router-apks/truck-router-v$version.apk"
$latest = "gs://truck-router-apks/truck-router-latest.apk"
$url    = "https://storage.googleapis.com/truck-router-apks/truck-router-v$version.apk"

Write-Host "Subindo para GCS..." -ForegroundColor Cyan
gcloud storage cp $apk $dest --project=maps-route-495614
gcloud storage cp $apk $latest --project=maps-route-495614

Write-Host ""
Write-Host "Publicado!" -ForegroundColor Green
Write-Host "Versao : $version"
Write-Host "Link   : $url"
Write-Host "Latest : https://storage.googleapis.com/truck-router-apks/truck-router-latest.apk"
