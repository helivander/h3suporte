@echo off
chcp 65001 >nul
:: ============================================================================
::  H3 Suporte - Definir senha de acesso nao-supervisionado (por cliente)
::  Uso: rodar na maquina do cliente DURANTE a sessao remota.
::  Define uma senha permanente UNICA, sem nada embutido no instalador.
::  Requer: H3 Suporte INSTALADO (servico) + privilegios de administrador.
:: ============================================================================

:: --- 1) Auto-elevar para administrador ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

setlocal enabledelayedexpansion
title H3 Suporte - Definir senha permanente
echo ============================================================
echo   H3 SUPORTE - Senha de acesso nao-supervisionado
echo ============================================================
echo.

:: --- 2) Localizar o h3suporte.exe ---
set "EXE="

:: 2a) Pelo processo em execucao (mais confiavel - app aberto na sessao)
for /f "delims=" %%P in ('powershell -NoProfile -Command "(Get-Process h3suporte -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path)" 2^>nul') do set "EXE=%%P"

:: 2b) Pelo registro (InstallLocation)
if not defined EXE (
  for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\H3Suporte" /v InstallLocation 2^>nul ^| find "InstallLocation"') do (
    if exist "%%B\h3suporte.exe" set "EXE=%%B\h3suporte.exe"
  )
)

:: 2c) Caminhos comuns
if not defined EXE (
  for %%D in ("%ProgramFiles%\H3Suporte" "%ProgramFiles(x86)%\H3Suporte" "%ProgramW6432%\H3Suporte") do (
    if exist "%%~D\h3suporte.exe" set "EXE=%%~D\h3suporte.exe"
  )
)

if not defined EXE (
  echo [ERRO] Nao encontrei o h3suporte.exe INSTALADO.
  echo.
  echo Possiveis causas:
  echo   - O H3 Suporte esta rodando em modo PORTATIL ^(nao foi instalado^).
  echo   - Instale primeiro: abra o H3 Suporte e clique em "Instalar".
  echo.
  pause
  exit /b 1
)

echo Executavel encontrado:
echo    !EXE!
echo.

:: --- 3) Pedir a senha (mascarada) ---
for /f "delims=" %%S in ('powershell -NoProfile -Command "$p=Read-Host 'Digite a senha para ESTE cliente' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "PWD=%%S"

if not defined PWD (
  echo Senha vazia. Operacao cancelada.
  pause
  exit /b 1
)

:: --- 4) Aplicar ---
echo.
echo Aplicando senha...
"!EXE!" --password "!PWD!"
echo.
echo ------------------------------------------------------------
echo  Se apareceu "Done!" acima = senha definida com sucesso.
echo  O acesso nao-supervisionado ja funciona com essa senha.
echo.
echo  Se apareceu "Installation and administrative privileges
echo  required!" = o app NAO esta instalado (rodando portatil).
echo  Instale o H3 Suporte e rode este script de novo.
echo ------------------------------------------------------------
echo.
pause
