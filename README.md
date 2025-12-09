# Battery Monitor Overlay

PowerShell script that polls the local battery level and, when it drops below a configurable threshold while running on battery, displays a warning overlay with an image and dismiss button.

## Requirements

- Windows with PowerShell 5+.
- .NET desktop components for WPF (`PresentationFramework`) and optional `System.Drawing` (used to auto-generate a placeholder image).
- A warning image named `warning.jpg` in the same folder as the script. If missing, the script attempts to create one automatically.

## Usage

1. Save the script as `monitorBattery.ps1` in a writable folder alongside `warning.jpg`.
2. Launch PowerShell and run:

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\monitorBattery.ps1 `
     -CheckInterval 30 `
     -LowBatteryThreshold 35
   ```

   Parameters:

   - `CheckInterval` – seconds between battery checks (default `30`).
   - `LowBatteryThreshold` – percentage that triggers the warning when running on battery (default `35`).

3. The console will print the current charge and AC status each interval. When the battery falls below the threshold without AC power, a centered, top-most overlay appears. Monitoring pauses while the overlay is open, so the Close button stays responsive.
4. Click **Close Warning** to dismiss the overlay; monitoring resumes automatically. Connecting AC power or charging back above the threshold also closes the overlay.

## Notes

- Use `Ctrl+C` in the console to stop the monitor. The script ensures the overlay closes during cleanup.
- `Get-WmiObject Win32_Battery` is queried first; on devices without that class, it falls back to `System.Windows.Forms.SystemInformation.PowerStatus`.
- If you prefer the monitor to continue running while the overlay is displayed, move the polling loop to a background runspace or timer instead of using the modal approach.
