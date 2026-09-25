# Measures a *built* Bonehead Friend against the performance budget (CLAUDE.md: < 3% CPU idle,
# < 8% under load). Editor numbers lie, so this runs the exported exe with the game's own
# staging flag (main.gd `--perf-stage`) and reads the process counters from outside.
#
#   powershell -File tools\perf_measure.ps1 -Exe "C:\path\Bonehead Friend.exe" -Mode idle -Repeat 3
#
# Modes: empty (him alone) · idle (hot tub steaming, rank-25 bat glowing) · load (plus a pellet
# turret firing at him) · toybox (M3.9's desk: a spinner, a cradle, bubble wrap and a boombox kept
# going, and three kind generators; D73). The game runs on its own save slot and writes settings
# only to a file of its own. Fifteen seconds in, the game writes what it actually staged to
# user://perf_<mode>.txt — items on the desk, hits landed, Bones earned — and rewrites it every
# five seconds with the frame rate it held, how long it sat at the idle cap and the most bodies
# awake at once. That is printed last, because a turret that never found him would otherwise
# measure as idle, and a desk that never slept would measure as a regression.
#
# CPU is reported two ways: as a share of ONE core (what a profiler shows) and as a share of the
# whole machine (what Task Manager shows, which is the number a player complains about). GPU is
# the 3D engine utilisation of the process from the same counters Task Manager reads; it is
# absent on machines whose driver does not expose it.
#
# **One run is not a measurement** (D73). The process's own CPU time rises when the rest of the
# machine is busy — shared cores, a contended GPU driver — so the script also reports how busy
# everything else was, and with -Repeat it runs the stage several times and prints the minimum,
# which is the number to compare. Working set swings by a hundred megabytes between identical
# runs as Windows trims it; private bytes are printed beside it and are the steadier of the two.
#
# The report is read from the exe's user folder: the standard one, or the custom one an
# override.cfg beside the exe names (how a scratch build keeps off the player's files).

param(
	[Parameter(Mandatory = $true)][string]$Exe,
	[string]$Mode = "idle",
	[int]$WarmupSeconds = 20,
	[int]$SampleSeconds = 60,
	[int]$Repeat = 1
)

function Get-UserDir([string]$exe) {
	$override = Join-Path (Split-Path -Parent $exe) "override.cfg"
	if (Test-Path $override) {
		$custom = Select-String -Path $override -Pattern 'custom_user_dir_name\s*=\s*"([^"]+)"' |
			Select-Object -First 1
		if ($custom) { return Join-Path $env:APPDATA $custom.Matches[0].Groups[1].Value }
	}
	return Join-Path $env:APPDATA "Godot\app_userdata\Bonehead Friend"
}

function Measure-Once([int]$run) {
	$report = Join-Path (Get-UserDir $Exe) "perf_$Mode.txt"
	# A report left by an earlier run would be printed as this run's proof.
	Remove-Item $report -ErrorAction SilentlyContinue
	$proc = Start-Process -FilePath $Exe -ArgumentList @("--", "--perf-stage=$Mode") -PassThru
	try {
		Start-Sleep -Seconds $WarmupSeconds
		$proc.Refresh()
		if ($proc.HasExited) { throw "the game exited during warm-up" }
		$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
		$cpu0 = $proc.TotalProcessorTime.TotalSeconds
		$t0 = Get-Date

		# GPU and the whole machine: sampled a few times across the window.
		$gpuSamples = @()
		$busySamples = @()
		$slices = [Math]::Max(1, [int]($SampleSeconds / 5))
		for ($i = 0; $i -lt $slices; $i++) {
			Start-Sleep -Seconds 5
			try {
				$busySamples += (Get-Counter -Counter "\Processor(_Total)\% Processor Time" -ErrorAction Stop).CounterSamples[0].CookedValue
			} catch { }
			try {
				$paths = (Get-Counter -ListSet "GPU Engine" -ErrorAction Stop).PathsWithInstances |
					Where-Object { $_ -like "*pid_$($proc.Id)_*engtype_3D*" -and $_ -like "*Utilization Percentage*" }
				if ($paths) {
					$vals = (Get-Counter -Counter $paths -ErrorAction Stop).CounterSamples | ForEach-Object { $_.CookedValue }
					$gpuSamples += ($vals | Measure-Object -Sum).Sum
				}
			} catch { }
		}

		$proc.Refresh()
		$cpu1 = $proc.TotalProcessorTime.TotalSeconds
		$elapsed = ((Get-Date) - $t0).TotalSeconds
		$oneCore = 100.0 * ($cpu1 - $cpu0) / $elapsed
		$machine = $oneCore / $cores
		$others = -1.0
		if ($busySamples.Count -gt 0) {
			$others = [Math]::Max(0.0, ($busySamples | Measure-Object -Average).Average - $machine)
		}

		if ($Repeat -gt 1) { Write-Output ("--- run {0} of {1}" -f $run, $Repeat) }
		Write-Output ("mode            {0}" -f $Mode)
		Write-Output ("window          {0:N0} s after {1} s warm-up" -f $elapsed, $WarmupSeconds)
		Write-Output ("cpu, one core   {0:N2} %" -f $oneCore)
		Write-Output ("cpu, machine    {0:N2} %  ({1} logical cores)" -f $machine, $cores)
		if ($others -ge 0.0) {
			Write-Output ("everything else {0:N1} % of the machine{1}" -f $others,
				$(if ($others -gt 10.0) { "  (busy: repeat this when it is quieter)" } else { "" }))
		}
		if ($gpuSamples.Count -gt 0) {
			$gpu = ($gpuSamples | Measure-Object -Average).Average
			Write-Output ("gpu 3d          {0:N2} %" -f $gpu)
		} else {
			Write-Output "gpu 3d          (counter not available)"
		}
		Write-Output ("working set     {0} MB  (private {1} MB)" -f [Math]::Round($proc.WorkingSet64 / 1MB, 1),
			[Math]::Round($proc.PrivateMemorySize64 / 1MB, 1))
		if (Test-Path $report) {
			Get-Content $report | ForEach-Object { Write-Output ("stage           " + $_) }
		} else {
			Write-Output "stage           (no report written)"
		}
		return [pscustomobject]@{ OneCore = $oneCore; Machine = $machine }
	} finally {
		if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
	}
}

$results = @()
for ($run = 1; $run -le [Math]::Max(1, $Repeat); $run++) {
	# The lines are printed as they come; the numbers are kept for the summary.
	Measure-Once $run | ForEach-Object { if ($_ -is [string]) { Write-Output $_ } else { $results += $_ } }
}
if ($results.Count -gt 1) {
	$best = $results | Sort-Object OneCore | Select-Object -First 1
	Write-Output ("--- minimum of {0}: {1:N2} % of one core, {2:N2} % of the machine" -f $results.Count,
		$best.OneCore, $best.Machine)
}
