@echo off
title NCM staging tunnel  --  leave this window open
setlocal
set KEY=%USERPROFILE%\.ssh\lightsail-ncm.pem
set REMOTE=ubuntu@52.60.225.137

if not exist "%KEY%" (
  echo.
  echo   Key not found: %KEY%
  echo.
  pause
  exit /b 1
)

netstat -ano | findstr ":11790" | findstr "LISTENING" >nul 2>&1
if %errorlevel%==0 (
  echo.
  echo   Port 11790 is ALREADY BOUND - another tunnel is holding it.
  echo   Close that window ^(or end that agent's session^), then run this again.
  echo.
  netstat -ano | findstr ":11790" | findstr "LISTENING"
  echo.
  pause
  exit /b 1
)

:loop
echo [%time%] connecting  11790 -^> 127.0.0.1:11780  (Warden)
ssh -i "%KEY%" -N -L 11790:127.0.0.1:11780 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes %REMOTE%
echo [%time%] tunnel dropped - reconnecting in 5s.  Press Ctrl+C twice to stop.
timeout /t 5 /nobreak >nul
goto loop
