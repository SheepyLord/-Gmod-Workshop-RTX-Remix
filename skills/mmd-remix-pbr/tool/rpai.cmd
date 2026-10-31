@echo off
rem Remix PBR AI launcher: rpai run "E:\path\to\model.pmx"
setlocal
if "%RPAI_HOME%"=="" set "RPAI_HOME=%USERPROFILE%\.rpai"
if not exist "%RPAI_HOME%\venv\Scripts\python.exe" (
  echo The Python environment is missing. Run setup.ps1 first.
  exit /b 1
)
set "PYTHONPATH=%~dp0;%PYTHONPATH%"
"%RPAI_HOME%\venv\Scripts\python.exe" -m rpai %*
