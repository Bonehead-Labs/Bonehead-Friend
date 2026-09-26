# Makes a playtest build of Bonehead Friend and the one zip a tester needs (docs/playtest-plan.md).
#
#   powershell -ExecutionPolicy Bypass -File tools\make_playtest_build.ps1
#   powershell -ExecutionPolicy Bypass -File tools\make_playtest_build.ps1 -OutDir D:\builds
#   powershell -ExecutionPolicy Bypass -File tools\make_playtest_build.ps1 -UploadUrl "https://..."
#
# PowerShell rather than Git Bash because this is the machine's own shell and it is where a zip,
# a Desktop path and a quoted Windows path are all native. -ExecutionPolicy Bypass because a
# fresh Windows refuses to run any script file otherwise.
#
# In order:
#   1. A build id: the date, the short commit, and -dirty if the tree has changes the commit does
#      not (the editor's own rewrites of *.import files are ignored — they are not the game).
#   2. Data/build_stamp.txt, which the export carries because Data/*.txt is on the preset's
#      include list. The game reads it (BuildInfo): Settings shows it, F3 shows it, and every
#      session log and feedback note is stamped with it. Deleted again when this finishes,
#      whether it worked or not; it is gitignored in case it is ever left behind.
#   3. --export-release, headless, into a folder named for the build.
#   4. tools/pack_check.gd against the exe itself (the pack is embedded in it): every sprite,
#      scene, data file and the stamp must be inside, or no zip is made.
#   5. Beside the exe: README-PLAYTEST.txt for the tester, an override.cfg that gives the build
#      its own save folder (so a playtest on this PC never loads the developer's save, and the
#      developer's save never sees the playtest), and — only with -UploadUrl — a playtest.cfg
#      naming the endpoint. The endpoint is never written into the repository or the pack.
#   6. One zip of that folder in -OutDir. Its path and size are the last thing printed.

param(
	[string]$OutDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "Bonehead Friend playtest"),
	[string]$Godot = "C:\Users\George\Godot Projects\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
	[string]$Channel = "playtest",
	# The build's own save and log folder under %APPDATA%. Give a tester their own to keep two
	# people playing on one PC apart (e.g. -UserDirName "Bonehead Friend Playtest - Round 0").
	[string]$UserDirName = "Bonehead Friend Playtest",
	[string]$UploadUrl = "",
	[ValidateSet("multipart", "json")][string]$UploadFormat = "multipart",
	[string]$UploadField = "file",
	# One extra request header, e.g. "Authorization: Bearer abc123".
	[string]$UploadHeader = "",
	# Also bundle the logs into the upload queue on every quit, so they arrive without a button.
	[switch]$AutoUpload
)

$ErrorActionPreference = "Stop"
$Project = Split-Path -Parent $PSScriptRoot
$Stamp = Join-Path $Project "Data\build_stamp.txt"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# Start-Process rather than the call operator: PowerShell 5.1 turns every line a native exe
# writes to stderr into an error record, and under Stop the engine's first warning would abort
# the build. The handle is read before waiting, or ExitCode comes back empty (a 5.1 quirk).
function Invoke-Godot([string[]]$Arguments, [string]$LogPath) {
	$quoted = $Arguments | ForEach-Object {
		if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
	}
	$process = Start-Process -FilePath $Godot -ArgumentList ($quoted -join " ") -NoNewWindow -PassThru `
		-RedirectStandardOutput $LogPath -RedirectStandardError "$LogPath.err"
	$null = $process.Handle
	$process.WaitForExit()
	return $process.ExitCode
}

function Write-Text([string]$Path, [string[]]$Lines, [string]$Newline = "`n") {
	[System.IO.File]::WriteAllText($Path, ($Lines -join $Newline) + $Newline, $Utf8)
}

if (-not (Test-Path $Godot)) { throw "Godot 4.7.2 not found at $Godot (pass -Godot)" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is not on PATH" }

# --- 1. the build id ------------------------------------------------------------------------
$short = (& git -C $Project rev-parse --short HEAD).Trim()
$commit = (& git -C $Project rev-parse HEAD).Trim()
$changes = & git -C $Project status --porcelain -- . ':(exclude)*.import'
$dirty = if ($changes) { "-dirty" } else { "" }
$BuildId = "{0}-{1}{2}" -f (Get-Date -Format "yyyy-MM-dd"), $short, $dirty
$Name = "BoneheadFriend-$BuildId"
Write-Host "Build     $BuildId"
if ($dirty) { Write-Host "          (uncommitted changes are in this build)" }

# --- 2..4. stamp, export, check -----------------------------------------------------------
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Stage = Join-Path $OutDir $Name
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory $Stage | Out-Null
$Exe = Join-Path $Stage "Bonehead Friend.exe"
$ExportLog = Join-Path $env:TEMP "$Name-export.log"
$CheckLog = Join-Path $env:TEMP "$Name-packcheck.log"

Write-Text $Stamp @(
	"build_id=$BuildId",
	"channel=$Channel",
	"commit=$commit",
	"built_at=$(Get-Date -Format s)"
)
try {
	Write-Host "Export    ..."
	$code = Invoke-Godot @("--headless", "--path", $Project, "--export-release", "Windows Desktop", $Exe) $ExportLog
	if ($code -ne 0 -or -not (Test-Path $Exe)) { throw "export failed (exit $code) - see $ExportLog" }

	$code = Invoke-Godot @("--headless", "--path", $Project, "-s", "res://tools/pack_check.gd", "--",
		$Exe, "--require=res://Data/build_stamp.txt") $CheckLog
	Get-Content $CheckLog | Where-Object { $_ -match '^(pack|files|required|MISSING|ok|  )' } |
		ForEach-Object { Write-Host "Pack      $_" }
	if ($code -ne 0) { throw "the export is missing runtime files - see $CheckLog" }
} finally {
	Remove-Item $Stamp -ErrorAction SilentlyContinue
}

# The console wrapper is for developers reading a crash; a tester would only double-click the
# wrong one.
Get-ChildItem $Stage -Filter "*.console.exe" | Remove-Item

# --- 5. what goes beside the exe ----------------------------------------------------------
Write-Text (Join-Path $Stage "override.cfg") @(
	"[application]",
	"config/use_custom_user_dir=true",
	"config/custom_user_dir_name=""$UserDirName"""
)

if ($UploadUrl) {
	Write-Text (Join-Path $Stage "playtest.cfg") @(
		"[upload]",
		"url=""$UploadUrl""",
		"format=""$UploadFormat""",
		"file_field=""$UploadField""",
		"header=""$UploadHeader""",
		"auto_on_quit=$(if ($AutoUpload) { 'true' } else { 'false' })"
	)
	$Sending = @(
		"- Settings > Playtest > Send feedback sends your notes and the play log (see below)",
		"  straight to us. If you are offline it tries again the next time you start the game."
	)
	if ($AutoUpload) {
		$Sending += "- This build also sends the play log by itself each time you quit the game."
	}
} else {
	$Sending = @(
		"- When you are done (or any time you like), open Settings > Playtest > Send feedback.",
		"  It saves ONE zip file on your Desktop. Send that file back however is easiest -",
		"  email, chat, a drive link. It holds your notes and the play log described below."
	)
}

$Readme = Get-Content (Join-Path $PSScriptRoot "playtest_readme.txt") -Encoding UTF8 -Raw
$Readme = $Readme.Replace("{{BUILD_ID}}", $BuildId).Replace("{{DATA_DIR}}", "%APPDATA%\$UserDirName")
$Readme = $Readme.Replace("{{SENDING}}", ($Sending -join "`n"))
# CRLF: this file is opened by double-clicking it, and some of those Notepads are old.
Write-Text (Join-Path $Stage "README-PLAYTEST.txt") ($Readme.TrimEnd() -split "\r?\n") "`r`n"

# --- 6. the zip -------------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Zip = Join-Path $OutDir "$Name.zip"
if (Test-Path $Zip) { Remove-Item $Zip }
# The folder goes in the zip, not just its contents, so "Extract All" makes one tidy folder.
[System.IO.Compression.ZipFile]::CreateFromDirectory($Stage, $Zip,
	[System.IO.Compression.CompressionLevel]::Optimal, $true)

$Size = (Get-Item $Zip).Length / 1MB
Write-Host ("Uploader  {0}" -f $(if ($UploadUrl) { "on, to " + ([Uri]$UploadUrl).Host } else { "off (feedback is a zip the tester sends)" }))
Write-Host ("Zip       {0}  ({1:N1} MB)" -f $Zip, $Size)
