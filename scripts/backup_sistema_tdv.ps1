# Respaldo del Sistema TDV.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\scripts\backup_sistema_tdv.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\backup_sistema_tdv.ps1 -IncluirMedia
#   powershell -ExecutionPolicy Bypass -File .\scripts\backup_sistema_tdv.ps1 -DestinoExterno "\\NAS\Respaldos\SistemaTDV"
#
# - db.sqlite3 se copia con la API de SQLite (scripts\backup_db.py), no con
#   Copy-Item: asi la copia sale coherente aunque el sistema este encendido.
# - media\ es opcional porque pesa mucho; se recomienda semanal.
# - -DestinoExterno copia el respaldo del dia fuera del servidor (NAS o
#   carpeta de red). Un respaldo en el mismo disco no protege de una falla
#   del disco.
# - Todo queda registrado en runtime\logs\backup.log

param(
    [switch]$IncluirMedia,
    [int]$ConservarDias = 14,
    [string]$DestinoExterno = ""
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

$Logs = Join-Path $Root "runtime\logs"
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
Start-Transcript -LiteralPath (Join-Path $Logs "backup.log") -Append | Out-Null

$fallo = $false
try {
    $Python = Join-Path $Root ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $Python)) {
        throw "No se encontro el venv: $Python"
    }

    $DestinoRaiz = Join-Path $Root "backups"
    $Hoy = Get-Date -Format "yyyy-MM-dd"
    $DestinoDia = Join-Path $DestinoRaiz $Hoy
    New-Item -ItemType Directory -Force -Path $DestinoDia | Out-Null

    # ---- Base de datos (siempre) ----
    $destinoDb = Join-Path $DestinoDia "db.sqlite3"
    & $Python (Join-Path $PSScriptRoot "backup_db.py") $destinoDb
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo el respaldo de db.sqlite3 (codigo $LASTEXITCODE)."
    }

    # ---- media\ (opcional) ----
    if ($IncluirMedia) {
        $media = Join-Path $Root "media"
        if (Test-Path -LiteralPath $media) {
            $destinoMedia = Join-Path $DestinoDia "media"
            # /MIR copia solo cambios; /R:1 /W:1 evita cuelgues largos
            robocopy $media $destinoMedia /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
            # robocopy: codigos < 8 son exito
            if ($LASTEXITCODE -ge 8) {
                throw "robocopy fallo al copiar media (codigo $LASTEXITCODE)."
            }
            Write-Host "OK media -> backups\$Hoy\media\"
        } else {
            Write-Host "AVISO: no existe carpeta media\; se omite."
        }
    } else {
        Write-Host "media\ omitida (usar -IncluirMedia una vez por semana)."
    }

    # ---- Copia fuera del servidor (opcional) ----
    if ($DestinoExterno) {
        if (-not (Test-Path -LiteralPath $DestinoExterno)) {
            throw "No se puede acceder al destino externo: $DestinoExterno"
        }
        $externoDia = Join-Path $DestinoExterno $Hoy
        robocopy $DestinoDia $externoDia /E /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy fallo al copiar a $DestinoExterno (codigo $LASTEXITCODE)."
        }
        Write-Host "OK copia externa -> $externoDia"
    }

    Write-Host "Los Excel acumulativos no se respaldan aqui: viven en OneDrive/carpeta compartida."

    # ---- Rotacion: borrar respaldos mas viejos que $ConservarDias ----
    # Se usa la fecha del nombre de la carpeta (AAAA-MM-DD), no la fecha
    # de modificacion, para no borrar de mas ni de menos.
    $limite = (Get-Date).Date.AddDays(-$ConservarDias)
    $raices = @($DestinoRaiz)
    if ($DestinoExterno) { $raices += $DestinoExterno }

    foreach ($raiz in $raices) {
        Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } |
            ForEach-Object {
                $fecha = [datetime]::ParseExact($_.Name, "yyyy-MM-dd", $null)
                if ($fecha -lt $limite) {
                    Write-Host "Borrando respaldo viejo: $($_.FullName)"
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force
                }
            }
    }

    Write-Host "Backup terminado $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
}
catch {
    $fallo = $true
    Write-Host "ERROR: $($_.Exception.Message)"
}
finally {
    Stop-Transcript | Out-Null
}

if ($fallo) { exit 1 }
exit 0