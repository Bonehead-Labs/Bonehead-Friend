# Measures a *built* Bonehead Friend against the performance budget (CLAUDE.md: < 3% CPU idle,
# < 8% under load). Editor numbers lie, so this runs the exported exe with the game's own
# staging flag (main.gd `--perf-stage`) and reads the process counters from outside.
#
#   powershell -File tools\perf_measure.ps1 -Exe "C:\path\Bonehead Friend.exe" -Mode idle
#
# Modes: empty (him alone) · idle (hot tub steaming, rank-25 bat glowing) · load (plus a pellet
# turret firing at him). The game runs on its own save slot and never writes settings. Fifteen
# seconds in, the game writes what it actually staged to user://perf_<mode>.txt — items on the
# desk, hits landed, Bones earned — and that is printed last, because a turret that never found
# him would otherwise measure as idle and nobody would know.
#
# CPU is reported two ways: as a share of ONE core (what a profiler shows) and as a share of the
# whole machine (what Task Manager shows, which is the number a player complains about). GPU is
# the 3D engine utilisation of the process from the same counters Task Manager reads; it is
# absent on machines whose driver does not expose it.

param(
	[Parameter(Mandatory = $true)][string]$Exe,
	[string]$Mode = "idle",
	[int]$WarmupSeconds = 20,
	[int]$SampleSeconds = 60
)

$proc = Start-Process -FilePath $Exe -ArgumentList @("--", "--perf-stage=$Mode") -PassThru
try {
	Start-Sleep -Seconds $WarmupSeconds
	$proc.Refresh()
	if ($proc.HasExited) { throw "the game exited during warm-up" }
	$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
	$cpu0 = $proc.TotalProcessorTime.TotalSeconds
	$t0 = Get-Date

	# GPU: sample the per-process 3D engine counter a few times across the window.
	$gpuSamples = @()
	$slices = [Math]::Max(1, [int]($SampleSeconds / 5))
	for ($i = 0; $i -lt $slices; $i++) {
		Start-Sleep -Seconds 5
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
	$mem = [Math]::Round($proc.WorkingSet64 / 1MB, 1)

	Write-Output ("mode            {0}" -f $Mode)
	Write-Output ("window          {0:N0} s after {1} s warm-up" -f $elapsed, $WarmupSeconds)
	Write-Output ("cpu, one core   {0:N2} %" -f $oneCore)
	Write-Output ("cpu, machine    {0:N2} %  ({1} logical cores)" -f $machine, $cores)
	if ($gpuSamples.Count -gt 0) {
		$gpu = ($gpuSamples | Measure-Object -Average).Average
		Write-Output ("gpu 3d          {0:N2} %" -f $gpu)
	} else {
		Write-Output "gpu 3d          (counter not available)"
	}
	Write-Output ("working set     {0} MB" -f $mem)
	$report = Join-Path $env:APPDATA "Godot\app_userdata\Bonehead Friend\perf_$Mode.txt"
	if (Test-Path $report) {
		Get-Content $report | ForEach-Object { Write-Output ("stage           " + $_) }
	} else {
		Write-Output "stage           (no report written)"
	}
} finally {
	if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
