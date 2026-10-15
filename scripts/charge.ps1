# Equivalent PowerShell de scripts/charge.sh.
# Lance le test de charge k6 (le meme que celui de l'analyse automatique)
# contre un service, et affiche le resume de k6.
# A lancer depuis la racine du depot taskflow-gitops.
# Usage : charge.ps1 [cible]   ex. charge.ps1 http://taskflow
param(
  [string]$Cible = "http://taskflow"
)

$scenario = Join-Path (Get-Location) "exemples\robustesse\configmap-k6.yaml"
if (-not (Test-Path $scenario)) {
  Write-Host "Scenario introuvable : $scenario (lancez le script depuis la racine du depot)" -ForegroundColor Red
  exit 1
}

# Extrait le script JS de la ConfigMap (lignes apres 'robustesse.js: |', indentation de 4 espaces retiree).
$lines = Get-Content $scenario -Encoding UTF8
$start = ($lines | Select-String -Pattern 'robustesse\.js: \|' | Select-Object -First 1).LineNumber
if (-not $start) { Write-Host "Bloc robustesse.js introuvable" -ForegroundColor Red; exit 1 }
$js = ($lines[$start..($lines.Count - 1)] | ForEach-Object { $_ -replace '^    ', '' }) -join "`n"
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($js))

Write-Host "Test de charge k6 sur $Cible (30 s, 5 utilisateurs virtuels)..."
$name = "k6-" + [DateTimeOffset]::Now.ToUnixTimeSeconds()
kubectl -n taskflow run $name --rm -i --restart=Never --quiet `
  --image=grafana/k6:latest --image-pull-policy=IfNotPresent `
  --env="TARGET=$Cible" --command -- sh -c "echo $b64 | base64 -d > /tmp/robustesse.js && k6 run /tmp/robustesse.js"
$code = $LASTEXITCODE

if ($code -eq 0) {
  Write-Host "Resultat : seuils respectes." -ForegroundColor Green
} else {
  Write-Host "Resultat : au moins un seuil n'est pas respecte (code $code)." -ForegroundColor Yellow
}
exit $code