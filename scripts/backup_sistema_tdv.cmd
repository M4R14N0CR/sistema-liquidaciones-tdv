@echo off
REM Respaldo del Sistema TDV (usado por el Programador de tareas).
REM Diario (solo base):       backup_sistema_tdv.cmd
REM Semanal (base + media):   backup_sistema_tdv.cmd -IncluirMedia
REM Con copia fuera:          backup_sistema_tdv.cmd -DestinoExterno "\\NAS\Respaldos\SistemaTDV"
REM Los parametros se pasan tal cual al .ps1.
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup_sistema_tdv.ps1" %*
exit /b %ERRORLEVEL%