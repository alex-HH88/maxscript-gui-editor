@echo off
setlocal EnableDelayedExpansion
title MAXScript GUI Editor — Installer

echo.
echo  =============================================
echo   MAXScript GUI Editor — Windows Installer
echo  =============================================
echo.

:: --- Locate Python 3 ---
set PYTHON=
for %%P in (python python3) do (
    if not defined PYTHON (
        %%P --version >nul 2>&1 && set PYTHON=%%P
    )
)
if not defined PYTHON (
    echo [ERROR] Python 3 not found. Install from https://www.python.org/downloads/
    echo         Make sure "Add Python to PATH" is checked during install.
    pause & exit /b 1
)

%PYTHON% -c "import sys; exit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python 3.9+ required. Detected:
    %PYTHON% --version
    pause & exit /b 1
)
echo [OK] Python found: & %PYTHON% --version

:: --- Install directory: %LOCALAPPDATA%\MAXScriptGUIEditor ---
set INSTALL_DIR=%LOCALAPPDATA%\MAXScriptGUIEditor
echo.
echo  Install directory: %INSTALL_DIR%
echo.

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

:: --- Copy app files ---
echo  Copying application files...
xcopy /E /I /Y /Q "%~dp0app"              "%INSTALL_DIR%\app\"   >nul
copy  /Y          "%~dp0main.py"           "%INSTALL_DIR%\"       >nul
copy  /Y          "%~dp0requirements.txt"  "%INSTALL_DIR%\"       >nul
copy  /Y          "%~dp0max_bridge_listener.ms" "%INSTALL_DIR%\"  >nul 2>&1
echo  [OK] Files copied.

:: --- Create venv ---
set VENV=%INSTALL_DIR%\venv
if not exist "%VENV%\Scripts\activate.bat" (
    echo  Creating virtual environment...
    %PYTHON% -m venv "%VENV%"
    if errorlevel 1 (
        echo [ERROR] Could not create virtual environment.
        pause & exit /b 1
    )
    echo  [OK] Virtual environment created.
)

:: --- Install PySide6 ---
echo  Installing PySide6 (this may take a minute)...
"%VENV%\Scripts\python.exe" -m pip install --upgrade pip -q
"%VENV%\Scripts\python.exe" -m pip install -r "%INSTALL_DIR%\requirements.txt" -q
if errorlevel 1 (
    echo [ERROR] pip install failed. Check internet connection.
    pause & exit /b 1
)
echo  [OK] PySide6 installed.

:: --- Write launcher batch ---
set LAUNCHER=%INSTALL_DIR%\launch.bat
(
    echo @echo off
    echo cd /d "%INSTALL_DIR%"
    echo "%VENV%\Scripts\pythonw.exe" main.py
) > "%LAUNCHER%"

:: --- Desktop shortcut via PowerShell (temp .ps1 to avoid ^ issues) ---
echo  Creating desktop shortcut...
set SHORTCUT=%USERPROFILE%\Desktop\MAXScript GUI Editor.lnk
set SM=%APPDATA%\Microsoft\Windows\Start Menu\Programs\MAXScript GUI Editor.lnk
set PS_TMP=%TEMP%\mge_shortcut.ps1

(
    echo $pyexe  = '%VENV%\Scripts\pythonw.exe'
    echo $workdir = '%INSTALL_DIR%'
    echo $ws = New-Object -ComObject WScript.Shell
    echo $s = $ws.CreateShortcut('%SHORTCUT%'^)
    echo $s.TargetPath = $pyexe
    echo $s.Arguments = 'main.py'
    echo $s.WorkingDirectory = $workdir
    echo $s.Description = 'MAXScript GUI Editor'
    echo $s.Save(^)
    echo $s2 = $ws.CreateShortcut('%SM%'^)
    echo $s2.TargetPath = $pyexe
    echo $s2.Arguments = 'main.py'
    echo $s2.WorkingDirectory = $workdir
    echo $s2.Description = 'MAXScript GUI Editor'
    echo $s2.Save(^)
) > "%PS_TMP%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_TMP%" >nul 2>&1
del "%PS_TMP%" >nul 2>&1

if exist "%SHORTCUT%" (
    echo  [OK] Desktop shortcut created.
) else (
    echo  [WARN] Shortcut could not be created - you can still launch via:
    echo         "%INSTALL_DIR%\launch.bat"
)

echo.
echo  =============================================
echo   Installation complete!
echo.
echo   Launch:  Desktop shortcut  or
echo            "%LAUNCHER%"
echo.
echo   3ds Max bridge:
echo     Scripting ^> Run Script ^>
echo     "%INSTALL_DIR%\max_bridge_listener.ms"
echo  =============================================
echo.
pause
