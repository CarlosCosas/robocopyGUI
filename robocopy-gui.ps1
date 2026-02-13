<#
.SYNOPSIS
GUI wrapper for robocopy.ps1 enterprise script

.DESCRIPTION
Simple Windows Forms GUI to configure and execute the robocopy script
without needing to use command line parameters.

.NOTES
Requires: robocopy.ps1 in the same directory
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RobocopyScript = Join-Path $ScriptDir "robocopy.ps1"

# Verify robocopy.ps1 exists
if (!(Test-Path $RobocopyScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Cannot find robocopy.ps1 in the same directory.`n`nExpected path: $RobocopyScript",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit
}

# Create form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Robocopy Enterprise GUI"
$form.Size = New-Object System.Drawing.Size(600, 550)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Source folders section
$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Location = New-Object System.Drawing.Point(10, 15)
$lblSource.Size = New-Object System.Drawing.Size(280, 20)
$lblSource.Text = "Source folders:"
$form.Controls.Add($lblSource)

$listSource = New-Object System.Windows.Forms.ListBox
$listSource.Location = New-Object System.Drawing.Point(10, 40)
$listSource.Size = New-Object System.Drawing.Size(450, 120)
$form.Controls.Add($listSource)

$btnAddSource = New-Object System.Windows.Forms.Button
$btnAddSource.Location = New-Object System.Drawing.Point(470, 40)
$btnAddSource.Size = New-Object System.Drawing.Size(100, 30)
$btnAddSource.Text = "Add..."
$btnAddSource.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select source folder"

    if ($folderBrowser.ShowDialog() -eq "OK") {
        $listSource.Items.Add($folderBrowser.SelectedPath)
    }
})
$form.Controls.Add($btnAddSource)

$btnRemoveSource = New-Object System.Windows.Forms.Button
$btnRemoveSource.Location = New-Object System.Drawing.Point(470, 80)
$btnRemoveSource.Size = New-Object System.Drawing.Size(100, 30)
$btnRemoveSource.Text = "Remove"
$btnRemoveSource.Add_Click({
    if ($listSource.SelectedIndex -ge 0) {
        $listSource.Items.RemoveAt($listSource.SelectedIndex)
    }
})
$form.Controls.Add($btnRemoveSource)

# Destination section
$lblDest = New-Object System.Windows.Forms.Label
$lblDest.Location = New-Object System.Drawing.Point(10, 175)
$lblDest.Size = New-Object System.Drawing.Size(280, 20)
$lblDest.Text = "Destination folder:"
$form.Controls.Add($lblDest)

$txtDestination = New-Object System.Windows.Forms.TextBox
$txtDestination.Location = New-Object System.Drawing.Point(10, 200)
$txtDestination.Size = New-Object System.Drawing.Size(450, 25)
$txtDestination.ReadOnly = $true
$form.Controls.Add($txtDestination)

$btnBrowseDest = New-Object System.Windows.Forms.Button
$btnBrowseDest.Location = New-Object System.Drawing.Point(470, 198)
$btnBrowseDest.Size = New-Object System.Drawing.Size(100, 25)
$btnBrowseDest.Text = "Browse..."
$btnBrowseDest.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select destination folder"

    if ($folderBrowser.ShowDialog() -eq "OK") {
        $txtDestination.Text = $folderBrowser.SelectedPath
    }
})
$form.Controls.Add($btnBrowseDest)

# Options section
$grpOptions = New-Object System.Windows.Forms.GroupBox
$grpOptions.Location = New-Object System.Drawing.Point(10, 240)
$grpOptions.Size = New-Object System.Drawing.Size(560, 160)
$grpOptions.Text = "Options"
$form.Controls.Add($grpOptions)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Location = New-Object System.Drawing.Point(15, 25)
$chkDryRun.Size = New-Object System.Drawing.Size(250, 20)
$chkDryRun.Text = "Simulation (DryRun) - do not copy"
$grpOptions.Controls.Add($chkDryRun)

$chkValidate = New-Object System.Windows.Forms.CheckBox
$chkValidate.Location = New-Object System.Drawing.Point(15, 50)
$chkValidate.Size = New-Object System.Drawing.Size(250, 20)
$chkValidate.Text = "Validation - analyze differences only"
$grpOptions.Controls.Add($chkValidate)

$chkParallel = New-Object System.Windows.Forms.CheckBox
$chkParallel.Location = New-Object System.Drawing.Point(15, 75)
$chkParallel.Size = New-Object System.Drawing.Size(250, 20)
$chkParallel.Text = "Parallel execution"
$grpOptions.Controls.Add($chkParallel)

$chkLog = New-Object System.Windows.Forms.CheckBox
$chkLog.Location = New-Object System.Drawing.Point(280, 25)
$chkLog.Size = New-Object System.Drawing.Size(250, 20)
$chkLog.Text = "Save log"
$grpOptions.Controls.Add($chkLog)

$chkExportJson = New-Object System.Windows.Forms.CheckBox
$chkExportJson.Location = New-Object System.Drawing.Point(280, 50)
$chkExportJson.Size = New-Object System.Drawing.Size(250, 20)
$chkExportJson.Text = "Export JSON summary"
$grpOptions.Controls.Add($chkExportJson)

$chkFailFast = New-Object System.Windows.Forms.CheckBox
$chkFailFast.Location = New-Object System.Drawing.Point(280, 75)
$chkFailFast.Size = New-Object System.Drawing.Size(250, 20)
$chkFailFast.Text = "Fail-Fast (stop on errors)"
$grpOptions.Controls.Add($chkFailFast)

# MT threads
$lblMT = New-Object System.Windows.Forms.Label
$lblMT.Location = New-Object System.Drawing.Point(15, 105)
$lblMT.Size = New-Object System.Drawing.Size(150, 20)
$lblMT.Text = "Robocopy threads (MT):"
$grpOptions.Controls.Add($lblMT)

$numMT = New-Object System.Windows.Forms.NumericUpDown
$numMT.Location = New-Object System.Drawing.Point(170, 103)
$numMT.Size = New-Object System.Drawing.Size(80, 25)
$numMT.Minimum = 1
$numMT.Maximum = 128
$numMT.Value = 16
$grpOptions.Controls.Add($numMT)

# ThrottleLimit
$lblThrottle = New-Object System.Windows.Forms.Label
$lblThrottle.Location = New-Object System.Drawing.Point(280, 105)
$lblThrottle.Size = New-Object System.Drawing.Size(170, 20)
$lblThrottle.Text = "Parallel limit (folders):"
$grpOptions.Controls.Add($lblThrottle)

$numThrottle = New-Object System.Windows.Forms.NumericUpDown
$numThrottle.Location = New-Object System.Drawing.Point(455, 103)
$numThrottle.Size = New-Object System.Drawing.Size(80, 25)
$numThrottle.Minimum = 1
$numThrottle.Maximum = 32
$numThrottle.Value = 4
$grpOptions.Controls.Add($numThrottle)

# Execute button
$btnExecute = New-Object System.Windows.Forms.Button
$btnExecute.Location = New-Object System.Drawing.Point(360, 420)
$btnExecute.Size = New-Object System.Drawing.Size(100, 35)
$btnExecute.Text = "Execute"
$btnExecute.BackColor = [System.Drawing.Color]::LightGreen
$btnExecute.Add_Click({
    # Validation
    if ($listSource.Items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "You must add at least one source folder.",
            "Validation",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    if ([string]::IsNullOrWhiteSpace($txtDestination.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            "You must select a destination folder.",
            "Validation",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    # Build command
    $params = @()
    
    # Add all source folders
    foreach ($source in $listSource.Items) {
        $params += "`"$source`""
    }
    
    # Add destination
    $params += "`"$($txtDestination.Text)`""
    
    # Add switches
    if ($chkDryRun.Checked) { $params += "-DryRun" }
    if ($chkValidate.Checked) { $params += "-Validate" }
    if ($chkParallel.Checked) { $params += "-Parallel" }
    if ($chkLog.Checked) { $params += "-Log" }
    if ($chkExportJson.Checked) { $params += "-ExportJson" }
    if ($chkFailFast.Checked) { $params += "-FailFast" }
    
    # Add numeric parameters
    $params += "-MT"
    $params += $numMT.Value
    $params += "-ThrottleLimit"
    $params += $numThrottle.Value
    
    # Build command string
    $command = "& `"$RobocopyScript`" " + ($params -join " ")

    # Confirm execution
    $message = "The following will be executed:`n`n$command`n`nContinue?"
    $result = [System.Windows.Forms.MessageBox]::Show(
        $message,
        "Confirm execution",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -eq "Yes") {
        # Execute in new PowerShell window
        $psCommand = "PowerShell -NoExit -ExecutionPolicy Bypass -Command `"$command`""
        Start-Process "cmd.exe" -ArgumentList "/c $psCommand"

        [System.Windows.Forms.MessageBox]::Show(
            "Script running in PowerShell window.",
            "Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
})
$form.Controls.Add($btnExecute)

# Cancel button
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Location = New-Object System.Drawing.Point(470, 420)
$btnCancel.Size = New-Object System.Drawing.Size(100, 35)
$btnCancel.Text = "Exit"
$btnCancel.Add_Click({
    $form.Close()
})
$form.Controls.Add($btnCancel)

# Show form
[void]$form.ShowDialog()
