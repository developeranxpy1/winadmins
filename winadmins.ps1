#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ElevatedLaunch,
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$stateDirectory = Join-Path $env:ProgramData 'WINADMINS'
$statePath      = Join-Path $stateDirectory 'state.json'
$specialKey     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
$policyKey      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$sourceUrl      = 'https://winadmins.vercel.app/'
$defaultPassword = '731235'

function Test-IsAdministrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enable-LogonScreenVisibility {
    param(
        [Parameter(Mandatory = $true)][string]$AccountName
    )

    if (-not (Test-Path -LiteralPath $specialKey)) {
        New-Item -Path $specialKey -Force | Out-Null
    }

    New-ItemProperty -Path $specialKey -Name $AccountName `
        -PropertyType DWord -Value 1 -Force | Out-Null

    New-ItemProperty -Path $policyKey -Name 'EnumerateLocalUsers' `
        -PropertyType DWord -Value 1 -Force | Out-Null
}

function Save-OriginalState {
    param(
        [Parameter(Mandatory = $true)]$Admin
    )

    if (Test-Path -LiteralPath $statePath) { return }

    $specialValue        = $null
    $specialValueExisted = $false
    if (Test-Path -LiteralPath $specialKey) {
        $props = Get-ItemProperty -Path $specialKey -Name $Admin.Name -ErrorAction SilentlyContinue
        if ($null -ne $props) {
            $specialValue        = $props.($Admin.Name)
            $specialValueExisted = $true
        }
    }

    $policyValue        = $null
    $policyValueExisted = $false
    $policyProps = Get-ItemProperty -Path $policyKey -Name 'EnumerateLocalUsers' -ErrorAction SilentlyContinue
    if ($null -ne $policyProps) {
        $policyValue        = $policyProps.EnumerateLocalUsers
        $policyValueExisted = $true
    }

    $state = [PSCustomObject]@{
        AccountName                 = $Admin.Name
        AccountEnabled              = [bool]$Admin.Enabled
        SpecialAccountsKeyExisted   = (Test-Path -LiteralPath $specialKey)
        SpecialAccountsValueExisted = $specialValueExisted
        SpecialAccountsValue        = $specialValue
        EnumerateLocalUsersExisted  = $policyValueExisted
        EnumerateLocalUsersValue    = $policyValue
    }

    if (-not (Test-Path -LiteralPath $stateDirectory)) {
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    }

    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Invoke-Revert {
    param(
        [Parameter(Mandatory = $true)]$Admin
    )

    $state = $null
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        }
        catch {
            $state = $null
        }
    }

    $restoreEnabled      = $false
    $specialValueExisted = $false
    $specialValue        = $null
    $specialKeyExisted   = $false
    $policyValueExisted  = $false
    $policyValue         = $null

    if ($null -ne $state) {
        $restoreEnabled      = [bool]$state.AccountEnabled
        $specialValueExisted = [bool]$state.SpecialAccountsValueExisted
        $specialValue        = $state.SpecialAccountsValue
        $specialKeyExisted   = [bool]$state.SpecialAccountsKeyExisted
        $policyValueExisted  = [bool]$state.EnumerateLocalUsersExisted
        $policyValue         = $state.EnumerateLocalUsersValue
        Write-Host 'Found saved state; restoring original values.' -ForegroundColor Cyan
    }
    else {
        Write-Host 'No saved state found; using safe defaults.' -ForegroundColor DarkYellow
    }

    Write-Host ''
    Write-Host 'Reverting changes...' -ForegroundColor Yellow

    $current = Get-LocalUser -Name $Admin.Name
    if ($restoreEnabled) {
        if (-not $current.Enabled) { Enable-LocalUser -Name $Admin.Name }
        Write-Host '  Account state restored: enabled.' -ForegroundColor Green
    }
    else {
        if ($current.Enabled) { Disable-LocalUser -Name $Admin.Name }
        Write-Host '  Account state restored: disabled.' -ForegroundColor Green
    }

    if ($specialValueExisted) {
        if (-not (Test-Path -LiteralPath $specialKey)) {
            New-Item -Path $specialKey -Force | Out-Null
        }
        New-ItemProperty -Path $specialKey -Name $Admin.Name `
            -PropertyType DWord -Value ([int]$specialValue) -Force | Out-Null
        Write-Host "  Sign-in visibility restored: $specialValue." -ForegroundColor Green
    }
    else {
        if (Test-Path -LiteralPath $specialKey) {
            Remove-ItemProperty -Path $specialKey -Name $Admin.Name -ErrorAction SilentlyContinue
            if (-not $specialKeyExisted) {
                $remaining = @(
                    (Get-ItemProperty -Path $specialKey -ErrorAction SilentlyContinue).PSObject.Properties |
                        Where-Object { $_.Name -notlike 'PS*' }
                )
                if ($remaining.Count -eq 0) {
                    Remove-Item -Path $specialKey -Force -ErrorAction SilentlyContinue
                }
            }
        }
        Write-Host '  Sign-in visibility entry removed.' -ForegroundColor Green
    }

    if ($policyValueExisted) {
        New-ItemProperty -Path $policyKey -Name 'EnumerateLocalUsers' `
            -PropertyType DWord -Value ([int]$policyValue) -Force | Out-Null
        Write-Host "  EnumerateLocalUsers restored: $policyValue." -ForegroundColor Green
    }
    else {
        Remove-ItemProperty -Path $policyKey -Name 'EnumerateLocalUsers' -ErrorAction SilentlyContinue
        Write-Host '  EnumerateLocalUsers entry removed.' -ForegroundColor Green
    }

    if (Test-Path -LiteralPath $statePath) {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path -LiteralPath $stateDirectory) -and
        -not (Get-ChildItem -LiteralPath $stateDirectory -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $stateDirectory -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host 'Revert complete. Everything is back to its original state.' -ForegroundColor Green
    Write-Host 'Note: the account keeps the default password. Change it after your first sign-in.' -ForegroundColor DarkYellow
}

# -----------------------------------------------------------------------------
#  Self-elevation: works from cmd, PowerShell, Run box, shortcuts, and irm | iex
# -----------------------------------------------------------------------------
$scriptPath = $PSCommandPath
$isPiped    = ($env:WINADMINS_PIPED -eq '1') -or [string]::IsNullOrEmpty($scriptPath)

if (-not (Test-IsAdministrator)) {
    Write-Host 'Requesting administrator privileges (UAC prompt)...' -ForegroundColor Yellow

    if ($isPiped) {
        # Running from memory (irm ... | iex). Re-run the same one-liner elevated.
        $innerCommand     = "irm '{0}?raw=1' | iex" -f $sourceUrl
        $arguments        = '-NoProfile -ExecutionPolicy Bypass -Command "{0}"' -f $innerCommand
        $workingDirectory = $env:SystemRoot
    }
    else {
        $workingDirectory = Split-Path -Parent $scriptPath
        if ([string]::IsNullOrEmpty($workingDirectory) -or $workingDirectory -like '\\*') {
            $workingDirectory = $env:SystemRoot
        }

        $arguments = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', ('"{0}"' -f $scriptPath)
            '-ElevatedLaunch'
        )
        if ($Revert) {
            $arguments += '-Revert'
        }
    }

    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path `
            -Verb RunAs `
            -ArgumentList $arguments `
            -WorkingDirectory $workingDirectory
    }
    catch {
        Write-Host 'Elevation was cancelled or failed.' -ForegroundColor Red
        Read-Host 'Press Enter to close' | Out-Null
        if ($isPiped) { return }
        exit 1
    }

    if ($isPiped) { return }
    exit
}

# -----------------------------------------------------------------------------
#  ASCII ART - h1: WINADMINS / h2: created by Frosty
# -----------------------------------------------------------------------------
$h1 = @'

██╗    ██╗ ██╗ ███╗   ██╗  █████╗  ██████╗  ███╗   ███╗ ██╗ ███╗   ██╗ ███████╗
██║    ██║ ██║ ████╗  ██║ ██╔══██╗ ██╔══██╗ ████╗ ████║ ██║ ████╗  ██║ ██╔════╝
██║ █╗ ██║ ██║ ██╔██╗ ██║ ███████║ ██║  ██║ ██╔████╔██║ ██║ ██╔██╗ ██║ ███████╗
██║███╗██║ ██║ ██║╚██╗██║ ██╔══██║ ██║  ██║ ██║╚██╔╝██║ ██║ ██║╚██╗██║ ╚════██║
╚███╔███╔╝ ██║ ██║ ╚████║ ██║  ██║ ██████╔╝ ██║ ╚═╝ ██║ ██║ ██║ ╚████║ ███████║
 ╚══╝╚══╝  ╚═╝ ╚═╝  ╚═══╝ ╚═╝  ╚═╝ ╚═════╝  ╚═╝     ╚═╝ ╚═╝ ╚═╝  ╚═══╝ ╚══════╝

'@

$h2 = @'
             c r e a t e d   b y   F r o s t y

'@

foreach ($line in ($h1 -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $winPart   = $line.Substring(0, [Math]::Min(25, $line.Length))
    $adminPart = if ($line.Length -gt 26) { $line.Substring(26) } else { '' }

    Write-Host $winPart -ForegroundColor Blue -NoNewline
    Write-Host $adminPart -ForegroundColor Red
}

Write-Host $h2 -ForegroundColor Yellow

if (-not $Revert) {
    Write-Host ''
    Write-Host '  What do you want to do?' -ForegroundColor White
    Write-Host '    [1] Enable the built-in Administrator  (press Enter)' -ForegroundColor Cyan
    Write-Host '    [2] Undo everything / uninstall' -ForegroundColor Cyan
    Write-Host '    [Q] Quit' -ForegroundColor DarkGray

    do {
        $choice = (Read-Host '  Choose [1]').Trim()
    } while ($choice -notin @('', '1', '2', 'q', 'Q'))

    if ($choice -in @('q', 'Q')) { return }
    if ($choice -eq '2') { $Revert = $true }
}

$exitCode = 0

try {
    # -------------------------------------------------------------------------
    #  Locate the built-in Administrator by SID, not by localized name.
    # -------------------------------------------------------------------------
    $admin = Get-LocalUser |
        Where-Object { $_.SID.Value -match '-500$' } |
        Select-Object -First 1

    if (-not $admin) {
        throw 'Built-in Administrator account not found.'
    }

    $accountState = if ($admin.Enabled) { 'enabled' } else { 'disabled' }
    Write-Host "  Built-in Administrator: $($admin.Name) ($accountState)" -ForegroundColor Cyan

    if ($Revert) {
        Write-Host 'Undoing all changes...' -ForegroundColor Magenta
        Invoke-Revert -Admin $admin
    }
    else {
        # Snapshot the original state once so -Revert can restore it later.
        Save-OriginalState -Admin $admin

        # ---------------------------------------------------------------------
        #  Use the default username and password. Change the password after first sign-in.
        # ---------------------------------------------------------------------
        $passwordPlain = $defaultPassword
        $password      = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force

        Write-Host ''
        Write-Host 'Applying changes...' -ForegroundColor Yellow

        Set-LocalUser -Name $admin.Name -Password $password

        if (-not $admin.Enabled) {
            Enable-LocalUser -Name $admin.Name
        }

        # Make the account selectable on the Windows sign-in / lock screen.
        Enable-LogonScreenVisibility -AccountName $admin.Name

        $result = Get-LocalUser -Name $admin.Name

        Write-Host ''
        Write-Host '  Account status:' -ForegroundColor Green
        Write-Host "    Username : $($result.Name)"
        Write-Host "    Enabled  : $($result.Enabled)"

        # ---------------------------------------------------------------------
        #  Show credentials clearly and put the password on the clipboard.
        # ---------------------------------------------------------------------
        $titleLine    = 'DEFAULT CREDENTIALS'.PadLeft(40).PadRight(62)
        $userLine     = ('  Username: ' + $result.Name).PadRight(62)
        $passwordLine = ('  Password: ' + $passwordPlain).PadRight(62)

        $box = @(
            '+==============================================================+'
            ('|{0}|' -f $titleLine)
            '+==============================================================+'
            ('|{0}|' -f $userLine)
            ('|{0}|' -f $passwordLine)
            '+==============================================================+'
        ) -join [Environment]::NewLine

        Write-Host ''
        Write-Host $box -ForegroundColor Green
        Write-Host ''
        Write-Host "Default username: $($result.Name)" -ForegroundColor Red
        Write-Host "Default password: $defaultPassword. Change it after your first sign-in." -ForegroundColor Red
        Write-Host 'The password has also been copied to your clipboard.' -ForegroundColor Yellow

        try {
            Set-Clipboard -Value $passwordPlain
        }
        catch {
            Write-Host 'Could not copy to clipboard.' -ForegroundColor DarkYellow
        }

        Write-Host ''
        Write-Host 'Done. The built-in Administrator account is ready.' -ForegroundColor Green
        Write-Host 'Sign out or reboot to see it on the sign-in / lock screen.' -ForegroundColor Cyan
        Write-Host "If the tile is not listed, choose 'Other user' and sign in as $($result.Name) (or .\$($result.Name))." -ForegroundColor Cyan
        Write-Host ''
        if ($isPiped) {
            Write-Host 'To undo later, run the same one-liner again and choose [2].' -ForegroundColor DarkCyan
        }
        else {
            Write-Host 'To undo later, run this file again and choose [2].' -ForegroundColor DarkCyan
        }
    }
}
catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
finally {
    $passwordPlain = $null
    $password      = $null
}

if ($ElevatedLaunch -or $isPiped) {
    Write-Host ''
    Read-Host 'Press Enter to close' | Out-Null
}

if ($isPiped) { return }
exit $exitCode
