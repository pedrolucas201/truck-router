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

$scriptStart = Get-Date
Write-Host "Buildando v$version..." -ForegroundColor Cyan

# APP_VERSION carimba a versao em TODO evento do field_logs (FieldLog.appVersion).
# Sem isso, saber qual build gerou um log so dava por engenharia reversa nos eventos
# — e com dois motoristas em versoes diferentes ao mesmo tempo, isso ja deu errado.
flutter build apk --release --no-tree-shake-icons `
    "--dart-define-from-file=dart_defines.json" `
    "--dart-define=APP_VERSION=$version"

# $ErrorActionPreference = Stop NAO pega falha de executavel nativo: em 2026-09-09 o
# Gradle falhou, o script seguiu e subiu o APK do dia anterior (2.4.57) pro GCS, pro
# latest e pro App Distribution com o nome 2.4.58. Guarda dupla: codigo de saida E
# o APK tem que ser mais novo que o inicio deste script.
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build FALHOU (codigo $LASTEXITCODE). Nada foi publicado." -ForegroundColor Red
    exit 1
}

$apk    = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk) -or (Get-Item $apk).LastWriteTime -lt $scriptStart) {
    Write-Host "APK ausente ou mais velho que o inicio do build. Nada foi publicado." -ForegroundColor Red
    exit 1
}
# Assinatura: o release tem que sair do upload-keystore.jks (SHA-1 abaixo). Sem o
# key.properties o Gradle cai na chave de debug em silencio, e um APK de debug por cima
# da base instalada obriga todo motorista a desinstalar. Publicar so com a chave certa.
$releaseSha1 = "14e1e4af20d6d371cb2863fb28af201c1a7ba145"
$apksigner = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools\*\apksigner.bat" |
    Sort-Object Name | Select-Object -Last 1
$certs = & $apksigner.FullName verify --print-certs $apk 2>&1 | Out-String
if ($certs -notmatch "SHA-1 digest:\s*$releaseSha1") {
    Write-Host "APK NAO esta assinado com o upload-keystore (falta android/key.properties?). Nada foi publicado." -ForegroundColor Red
    exit 1
}

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
        # O commit de bump e SEMPRE o ultimo antes do release, entao o fallback ingenuo
        # (git log -1) mandava "chore: bump versao para X" como nota — o motorista abre a
        # notificacao, le isso e nao tem motivo nenhum pra instalar. Pega o primeiro
        # commit de verdade abaixo dele.
        $Notes = git log -10 --pretty=%s | Where-Object { $_ -notmatch "^chore: bump" } | Select-Object -First 1
        if (-not $Notes) { $Notes = git log -1 --pretty=%s }
        # Tira o prefixo Conventional ("fix(busca): ", "feat(terra): "). Ele existe
        # pro historico do git, nao pro motorista — na v2.4.45 a nota saiu com
        # "feat(terra):" na frente e teve que ser corrigida a mao pela API depois.
        $Notes = $Notes -replace '^[a-z]+(\([^)]+\))?!?:\s*', ''
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
