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
"%VENV%\Scripts\pip.exe" install --upgrade pip -q
"%VENV%\Scripts\pip.exe" install -r "%INSTALL_DIR%\requirements.txt" -q
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

:: --- Desktop shortcut via PowerShell ---
echo  Creating desktop shortcut...
set SHORTCUT=%USERPROFILE%\Desktop\MAXScript GUI Editor.lnk
powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s  = $ws.CreateShortcut('%SHORTCUT%'); ^
   $s.TargetPath  = '%VENV%\Scripts\pythonw.exe'; ^
   $s.Arguments   = 'main.py'; ^
   $s.WorkingDirectory = '%INSTALL_DIR%'; ^
   $s.Description = 'MAXScript GUI Editor'; ^
   $s.Save()"
if exist "%SHORTCUT%" (
    echo  [OK] Desktop shortcut created.
) else (
    echo  [WARN] Shortcut could not be created ^(no admin needed, check PowerShell policy^).
)

:: --- Start Menu shortcut ---
set SM=%APPDATA%\Microsoft\Windows\Start Menu\Programs\MAXScript GUI Editor.lnk
powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s  = $ws.CreateShortcut('%SM%'); ^
   $s.TargetPath  = '%VENV%\Scripts\pythonw.exe'; ^
   $s.Arguments   = 'main.py'; ^
   $s.WorkingDirectory = '%INSTALL_DIR%'; ^
   $s.Description = 'MAXScript GUI Editor'; ^
   $s.Save()" >nul 2>&1

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
