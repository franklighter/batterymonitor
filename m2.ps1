# BatteryMonitor.ps1
# Requires: Save a warning image as "warning.jpg" in the same directory

param(
    [int]$CheckInterval = 30,  # Check every 30 seconds
    [int]$LowBatteryThreshold = 101
)

# Get script directory for image path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$warningImage = Join-Path $scriptDir "warning.jpg"

# Check if warning image exists
if (-not (Test-Path $warningImage)) {
    # Create a simple warning image if none exists (requires .NET)
    try {
        Add-Type -AssemblyName System.Drawing
        $bitmap = New-Object System.Drawing.Bitmap(400, 300)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::Yellow)
        $font = New-Object System.Drawing.Font("Arial", 20)
        $brush = [System.Drawing.Brushes]::Black
        $graphics.DrawString("Low Battery Warning!", $font, $brush, 50, 120)
        $graphics.DrawString("Battery < 35%", $font, $brush, 100, 160)
        $bitmap.Save($warningImage, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $graphics.Dispose()
        $bitmap.Dispose()
        Write-Host "Created default warning image at: $warningImage"
    }
    catch {
        Write-Warning "Could not create warning image. Please add 'warning.jpg' manually to: $scriptDir"
        $warningImage = $null
    }
}

# Global variable to track if overlay is currently shown
$global:OverlayShown = $false
$global:OverlayWindow = $null

function Show-Overlay {
    if ($global:OverlayShown) { return }
    
    $global:OverlayShown = $true
    
    # Create WPF Window
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms
    
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Low Battery Warning" 
        WindowStyle="None" 
        ResizeMode="NoResize" 
        Topmost="True"
        Background="Transparent" 
        AllowsTransparency="True"
        Width="500" 
        Height="400"
        WindowStartupLocation="CenterScreen">
    <Border CornerRadius="10" Background="#FF4444" BorderThickness="3" BorderBrush="Yellow">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <Image Name="WarningImage" Grid.Row="0" Margin="20"/>
            <Button Name="CloseButton" Grid.Row="1" Content="Close Warning" 
                    Background="Yellow" Foreground="Black" FontWeight="Bold" 
                    FontSize="16" Margin="20" Padding="10" Cursor="Hand"/>
        </Grid>
    </Border>
</Window>
'@
    
    try {
        # Parse XAML
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        $global:OverlayWindow = [Windows.Markup.XamlReader]::Load($reader)
        $reader.Close()
        
        # Get controls
        $imageControl = $global:OverlayWindow.FindName("WarningImage")
        $closeButton = $global:OverlayWindow.FindName("CloseButton")
        
        # Load warning image if exists
        if ($warningImage -and (Test-Path $warningImage)) {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.UriSource = New-Object System.Uri($warningImage)
            $bitmap.EndInit()
            $imageControl.Source = $bitmap
        }
        
        # Set up button click event to close the dialog
        $closeButton.Add_Click({
            $global:OverlayShown = $false
            if ($global:OverlayWindow -ne $null) {
                $global:OverlayWindow.Close()
            }
        })
        
        # Ensure we clean up no matter how the window is closed
        $global:OverlayWindow.Add_Closed({
            $global:OverlayWindow = $null
            $global:OverlayShown = $false
        })
        
        # Make window click-through except for the button
        $global:OverlayWindow.Add_MouseDown({
            if ($_.OriginalSource -eq $global:OverlayWindow) {
                $_.Handled = $true
            }
        })
        
        Write-Host "Low battery warning displayed at $(Get-Date). Monitoring paused until window closes."
        $null = $global:OverlayWindow.ShowDialog()
    }
    catch {
        Write-Error "Failed to create overlay: $_"
        $global:OverlayShown = $false
    }
}

function Close-Overlay {
    if ($global:OverlayWindow -ne $null) {
        $global:OverlayWindow.Close()
        $global:OverlayWindow = $null
    }
    $global:OverlayShown = $false
}

function Get-BatteryStatus {
    try {
        # Method 1: Use WMI
        $battery = Get-WmiObject -Class Win32_Battery -ErrorAction Stop | Select-Object -First 1
        
        if ($battery) {
            return @{
                BatteryLevel = [int]$battery.EstimatedChargeRemaining
                PowerOnline = $battery.BatteryStatus -eq 2 -or $battery.PowerOnline
            }
        }
        
        # Method 2: Use System.Windows.Forms (fallback)
        Add-Type -AssemblyName System.Windows.Forms
        $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
        
        return @{
            BatteryLevel = [int]($powerStatus.BatteryLifePercent * 100)
            PowerOnline = $powerStatus.PowerLineStatus -eq "Online"
        }
    }
    catch {
        Write-Warning "Could not get battery status: $_"
        return $null
    }
}

# Main monitoring loop
Write-Host "Starting battery monitor (Threshold: $LowBatteryThreshold%, Check every: $CheckInterval seconds)"
Write-Host "Script directory: $scriptDir"
Write-Host "Press Ctrl+C to stop monitoring"

try {
    while ($true) {
        $status = Get-BatteryStatus
        
        if ($status) {
            Write-Host "Battery: $($status.BatteryLevel)%, AC Connected: $($status.PowerOnline)"
            
            if ($status.BatteryLevel -lt $LowBatteryThreshold -and -not $status.PowerOnline) {
                # Show overlay if not already shown
                if (-not $global:OverlayShown) {
                    Show-Overlay
                }
            }
            elseif ($status.PowerOnline -and $global:OverlayShown) {
                # AC power connected, close overlay
                Write-Host "AC power connected - closing warning"
                Close-Overlay
            }
            elseif ($status.BatteryLevel -ge $LowBatteryThreshold -and $global:OverlayShown) {
                # Battery charged above threshold
                Write-Host "Battery above threshold - closing warning"
                Close-Overlay
            }
        }
        
        # Wait for next check
        Start-Sleep -Seconds $CheckInterval
    }
}
finally {
    # Cleanup on exit
    Close-Overlay
    Write-Host "Battery monitor stopped"
}
