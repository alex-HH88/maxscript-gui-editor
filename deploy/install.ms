-- MAXScript GUI Editor — Installer
-- Run this script once to install the tool into 3ds Max.
-- After installation, find it under: Customize > Toolbars > Category: Tools
--
global TOOLS_VERSION = "1.19"

(
	local maxVer = (maxVersion())[1] / 1000
	if maxVer < 24 do (
		messageBox ("MAXScript GUI Editor v" + TOOLS_VERSION + "\n\nRequires 3ds Max 2022 or newer.\nDetected version: " + maxVer as string) title:"Install Error"
		return undefined
	)

	-- Determine paths
	local srcDir   = getFilenamePath (getThisScriptFilename())
	local srcFile  = srcDir + @"src\gui_editor.ms"
	local destDir  = (getDir #userScripts) + @"\MAXScriptGUIEditor\"
	local destFile = destDir + "gui_editor.ms"

	-- Validate source
	if not doesFileExist srcFile do (
		messageBox ("Source file not found:\n" + srcFile + "\n\nMake sure you extracted the full ZIP.") title:"Install Error"
		return undefined
	)

	-- Create destination folder
	if not doesFileExist destDir do makeDir destDir all:true

	-- Copy with verify
	if doesFileExist destFile do deleteFile destFile
	copyFile srcFile destFile
	if not doesFileExist destFile do (
		messageBox ("Copy failed.\nCould not write to:\n" + destFile) title:"Install Error"
		return undefined
	)

	-- Run the script (registers the macroScript)
	fileIn destFile quiet:true

	messageBox ("MAXScript GUI Editor v" + TOOLS_VERSION + " installed successfully!\n\nFind it under:\nCustomize > Toolbars > Category: Tools\n  → MAXScript GUI Editor\n\nDrag it to any toolbar or use the Hotkey editor to assign a shortcut.") title:"Installation Complete"
)
