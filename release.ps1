# release.ps1 — build APK release, sobe pro GCS e distribui no Firebase App Distribution
# Uso: .\release.ps1
#      .\release.ps1 -Notes "corrige o recalculo em loop e o botao azul no zoom"
#      .\release.ps1 -SkipDistribution     (so GCS, sem avisar os testers)
# Requer: flutter, gcloud (projeto maps-route-495614), firebase CLI logado.

param(
    [string]$Notes = "",
    [switch]$SkipDistribution
)

$ErrorActionPreference = "Stop"

# App Android no Firebase (projeto truck-router1) — mesmo appId do firebase_options.dart.
$firebaseAppId = "1:730093721780:android:ff70554973740ecc515fe1"
$testerGroup   = "motoristas"

$pubspec = Get-Content pubspec.yaml | Where-Object { $_ -match "^version:" }
if ($pubspec -match "version:\s*(.+)") {
    $version = $Matches[1].Trim()
} else {
    Write-Error "Nao foi possivel ler versao do pubspec.yaml"
    exit 1
}

Write-Host "Buildando v$version..." -ForegroundColor Cyan

# APP_VERSION carimba a versao em TODO evento do field_logs (FieldLog.appVersion).
# Sem isso, saber qual build gerou um log so dava por engenharia reversa nos eventos
# — e com dois motoristas em versoes diferentes ao mesmo tempo, isso ja deu errado.
flutter build apk --release --no-tree-shake-icons `
    "--dart-define-from-file=dart_defines.json" `
    "--dart-define=APP_VERSION=$version"

$apk    = "build\app\outputs\flutter-apk\app-release.apk"
$dest   = "gs://truck-router-apks/truck-router-v$version.apk"
$latest = "gs://truck-router-apks/truck-router-latest.apk"
$url    = "https://storage.googleapis.com/truck-router-apks/truck-router-v$version.apk"

Write-Host "Subindo para GCS..." -ForegroundColor Cyan
gcloud storage cp $apk $dest --project=maps-route-495614
gcloud storage cp $apk $latest --project=maps-route-495614

# Firebase App Distribution: notifica os testers e — o que mais importa — registra
# QUEM instalou QUAL versao. Ate hoje a versao rodando no caminhao so dava pra
# descobrir por engenharia reversa nos field_logs (quais eventos o build emitia).
if (-not $SkipDistribution) {
    if (-not $Notes) {
        $Notes = git log -1 --pretty=%s
    }
    Write-Host "Distribuindo para o grupo '$testerGroup'..." -ForegroundColor Cyan
    # Nao usa $ErrorActionPreference=Stop aqui: o APK ja esta no GCS, uma falha do
    # firebase CLI nao pode derrubar um release que ja foi publicado.
    try {
        firebase appdistribution:distribute $apk `
            --app $firebaseAppId `
            --groups $testerGroup `
            --release-notes "v$version - $Notes"
        if ($LASTEXITCODE -ne 0) { throw "firebase CLI saiu com codigo $LASTEXITCODE" }
        Write-Host "Testers notificados." -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "AVISO: App Distribution falhou ($_)." -ForegroundColor Yellow
        Write-Host "O APK ESTA publicado no GCS — so os testers nao foram avisados." -ForegroundColor Yellow
        Write-Host "Rode 'firebase login' e repita, ou mande o link abaixo na mao." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Publicado!" -ForegroundColor Green
Write-Host "Versao : $version"
Write-Host "Link   : $url"
Write-Host "Latest : https://storage.googleapis.com/truck-router-apks/truck-router-latest.apk"
