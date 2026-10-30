# One-shot demo deploy: formation server (Cloud Run) + web app (Firebase Hosting).
# Run from the teamix folder:  .\scripts\deploy_demo.ps1
# Then on any computer open https://teamix-309c0.web.app and sign in as admin@teamix.app.
$ErrorActionPreference = 'Stop'
$formation = 'https://teamix-formation-834695879387.asia-northeast3.run.app/'
$gcloud = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'

Write-Host '1/3 formation server (5-10 min)'
& $gcloud run deploy teamix-formation --source algorithm --region asia-northeast3 --project teamix-309c0 `
  --allow-unauthenticated --memory 1Gi --cpu 1 --max-instances 2 --timeout 300 --quiet
if ($LASTEXITCODE -ne 0) { throw 'Cloud Run deploy failed' }

Write-Host '2/3 web build'
flutter build web --release "--dart-define=FORMATION_URL=$formation"
if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }

Write-Host '3/3 hosting'
npx firebase deploy --only hosting --project teamix-309c0
if ($LASTEXITCODE -ne 0) { throw 'hosting deploy failed' }

Write-Host 'Done: https://teamix-309c0.web.app'
