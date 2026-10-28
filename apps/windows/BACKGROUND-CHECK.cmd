@echo off
setlocal
pushd "%~dp0"
start "" /wait Jieliu.exe --render-check > BACKGROUND-CHECK.log 2>&1
set "checkResult=%ERRORLEVEL%"
if "%checkResult%"=="0" (echo PASS - Offscreen checks completed.>> BACKGROUND-CHECK.log) else (echo FAIL - Exit code %checkResult%.>> BACKGROUND-CHECK.log)
popd
exit /b %checkResult%
