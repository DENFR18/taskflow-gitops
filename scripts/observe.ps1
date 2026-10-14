# Equivalent PowerShell de scripts/observe.sh.
# Envoie N requetes au service depuis l'interieur du cluster et compte les reponses
# par version et par code HTTP.
# Usage : .\scripts\observe.ps1 [service] [nombre]   ex. .\scripts\observe.ps1 taskflow 40
param(
  [string]$Service = "taskflow",
  [int]$Count = 40
)

$script = @'
for i in $(seq 1 __COUNT__); do
  r=$(curl -s -m 5 -w ' %{http_code}' http://__SERVICE__/)
  v=$(echo "$r" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
  echo "version=${v:-aucune} http=${r##* }"
done | sort | uniq -c
'@

# Retire les CR Windows, puis encode en base64 pour eviter tout probleme de guillemets.
$script = $script.Replace("__COUNT__", "$Count").Replace("__SERVICE__", $Service).Replace("`r", "")
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
$name = "observe-" + [DateTimeOffset]::Now.ToUnixTimeSeconds()

kubectl -n taskflow run $name --rm -i --restart=Never --quiet `
  --image=curlimages/curl:latest --command -- sh -c "echo $b64 | base64 -d | sh"