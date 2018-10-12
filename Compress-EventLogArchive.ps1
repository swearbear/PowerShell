<#
.Synopsis
   Send archived event logs to compressed folders
.DESCRIPTION
   Designed for use as a scheduled task, this script will compress archived event logs (.evtx).  The script takes a source directory and destination directory as input.  It also has a parameter to identify how many days old the archived event log should be to qualify for compression.  This script supports Windows Server versions 2008R2, 2012, 2012R2, 2016 and PowerShell versions v2 through v5.1.  In order to support older versions, this script doesn't use the Compress-Archive cmdlet introduced in PowerShell v5.
.EXAMPLE
   Compress-EventLogArchive.ps1 -Path C:\Windows\System32\winevt\Logs -Destination D:\Archived
   # Basic usage to compress all archived .evtx files in source directory and moving them to the destination directory.
.EXAMPLE
   Compress-EventLogArchive.ps1 D:\ForwardedEvents D:\Archived -DaysOld 30
   # Only compress archive .evtx files that are 30 days and older.
.EXAMPLE
   powershell.exe -noninteractive -executionpolicy bypass -file C:\Scripts\Compress-EventLogArchive.ps1 D:\ForwardedEvents D:\Archived -DaysOld 30
   # Using the script in a scheduled task.
.Notes
   Author: Chester Swearingen
   Version: 1.0
   Release: 10 Oct 2018
#>

param(
    [Parameter(Position=0)]
    [string]$Path,
    [Parameter(Position=1)]
    [string]$Destination,
    [int]$DaysOld = 0,
    [switch]$ShowProgress
)
    #[int]$Count = 1,    # for testing/debuging

# Required function for getting archived evtx files based on date
function Get-EventLogArchive {
    param(
        [Parameter(Mandatory=$true,ParameterSetName='FilePath')]
        [string] $FilePath,

        [Parameter(Mandatory=$true,ParameterSetName='LogName')]
        [string] $LogName,

        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [Alias('Cn')]
        [string] $ComputerName,

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [regex] $Pattern = '(?<=[\\\$\:\w\-_]*\-)\d{4}(\-\d{2}){5}(?=\-\d{3}.(evtx|zip)$)',

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [string] $FileExtension = ".evtx",

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [datetime] $NewerThan,

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [datetime] $OlderThan
    )

    function Get-ParsedDate {
        param(
            [Parameter(Mandatory=$true)]
            [string] $InputString,

            [Parameter(Mandatory=$true)]
            [string] $FormatString,

            [System.Globalization.CultureInfo] $Provider = [System.Globalization.CultureInfo]::InvariantCulture,

            [System.Globalization.DateTimeStyles] $DateTimeStyles = [System.Globalization.DateTimeStyles]::None,

            [switch] $Exact
        )

        [ref]$parsedDate = Get-Date
        if ([DateTime]::TryParseExact($InputString, $FormatString, $Provider, $DateTimeStyles, $parsedDate))
        {
            Write-Output $parsedDate.Value
        }
    }



    # ParameterSet 'LogName'
    if ($PSCmdlet.ParameterSetName -eq 'LogName')
    {
        $getWinEventParams = @{ListLog = $LogName}
        if ($PSBoundParameters.ContainsKey('ComputerName'))
        {
            # Get IPv4 addresses from the local computer for comparison with the $ComputerName parameter
            $IPv4Address = Get-WmiObject win32_networkadapterconfiguration |? {$_.IPEnabled -eq $true} |% {$_.IPAddress |? {$_ -match '(\d{1,3}\.){3}\d{1,3}'}}
            $localhost = "$env:COMPUTERNAME|localhost|127.0.0.1|$($IPv4Address -join '|')"
            if ($ComputerName -match $localhost)
            {
                $PSBoundParameters.Remove('ComputerName') > $null
            }
            else
            {
                $getWinEventParams.Add('ComputerName', $ComputerName)
            }
        }

        $log = Get-WinEvent @getWinEventParams

        if (($log) -and ($log.LogMode -eq 'AutoBackup'))
        {
            if ($getWinEventParams.ContainsKey('ComputerName'))
            {
                $FilePath = (Split-Path $log.LogFilePath -Parent)
                $drive = (Split-Path $FilePath -Qualifier) -replace '\:','$'
                $path = Split-Path $FilePath -NoQualifier
                $FilePath = Join-Path "\\$ComputerName\$drive" $path
            }
            else
            {
                $FilePath = (Split-Path $log.LogFilePath -Parent)
            }
        }
        else
        {
            Write-Error ("Archived event logs not found for LogName: {0} on computer: {1}" -f $LogName,$ComputerName) -ErrorAction Stop
            exit
        }
    }


    $Item = Get-Item $FilePath -ErrorAction Stop
    $Directory = $Item |? { $_ -is [System.IO.DirectoryInfo] }
    $Files = $Item |? { ($_ -is [System.IO.FileInfo]) -and ($_.Extension -eq $FileExtension) }
    if (-Not $Files)
    {
        if (-Not $Directory)
        {
            Write-Error "Event log archive not found at path: $Path" -ErrorAction Stop
            exit
        }
        else
        {
            $Files = Get-ChildItem $Directory -File -Filter "*$FileExtension"
            if (-Not $Files)
            {
                Write-Error "Event log archive not found at path: $Path" -ErrorAction Stop
                exit
            }
        }
    }

    $FileNameList = $Files |% { $_.FullName }

    $FileNameList |% {
        $dateString = $Pattern.Match($_).Value
        if ($dateString)
        {
            $ArchiveDate = Get-ParsedDate -InputString $dateString -FormatString "yyyy-MM-dd-HH-mm-ss"
            if (($NewerThan) -and ($OlderThan))
            {
                if ($ArchiveDate |? {($_ -gt $NewerThan) -and ($_ -lt $OlderThan)})
                {
                    New-Object pscustomobject -Property ([ordered]@{
                        ArchiveDate = $ArchiveDate
                        Path = $_
                    })
                }
            }
            elseif ($NewerThan)
            {
                if ($ArchiveDate |? {$_ -gt $NewerThan})
                {
                    New-Object pscustomobject -Property ([ordered]@{
                        ArchiveDate = $ArchiveDate
                        Path = $_
                    })
                }
            }
            elseif ($OlderThan)
            {
                if ($ArchiveDate |? {$_ -lt $OlderThan})
                {
                    New-Object pscustomobject -Property ([ordered]@{
                        ArchiveDate = $ArchiveDate
                        Path = $_
                    })
                }
            }
            else
            {
                New-Object pscustomobject -Property ([ordered]@{
                    ArchiveDate = $ArchiveDate
                    Path = $_
                })
            }
        }
    }
}

# Create destination directory and don't tell me if it already exists, or give me output when it creates it.
function mkdir-quiet ($path) {
    try {
        mkdir $path -ea stop > $null
    } catch {
        if ($_.CategoryInfo.Category -ne "ResourceExists") {
            throw $_
        }
    }
}

# Get the matching, evtx filepaths.
# Declare variable as string array in case only one value is assigned
$ArchivedLogs = @(Get-EventLogArchive -FilePath $Path -FileExtension '.evtx' -OlderThan (Get-Date).AddDays(-$DaysOld) |sort Path)

# Test for found files, exit script if none.
if (($ArchivedLogs -eq $null) -or ($ArchivedLogs.Length -eq 0)) {
    Write-Error "No archived event logs found."
    exit
}

mkdir-quiet $Destination

# Import the assembly necessary for file compression.
# This is necessary for hosts < Windows10/Server2016.
Add-Type -Assembly "System.IO.Compression.FileSystem"

# Used a for loop instead of foreach, apparently for no good reason.
for ($i=0; $i -lt $ArchivedLogs.Count; $i++) {

    # Progress bar if selected and running interactively
    if ($ShowProgress) {
        $params = @{
            Id = 0
            Activity = 'Compressing Event Logs'
            Status = "Processing $($i+1) of $($ArchivedLogs.count)"
            CurrentOperation = $log
            PercentComplete = (($i/$ArchivedLogs.Count) * 100)
        }
        Write-Progress @params
    }
    
    # Make a subdirectory named for the year the archive was created
    $DestYearDir = Join-Path $Destination $ArchivedLogs[$i].ArchiveDate.Year
    mkdir-quiet $DestYearDir

    # Derive the compressed directory name from the evtx filename
    # Use this to make a temp directory
    $zipDirectoryName = $ArchivedLogs[$i].Path -replace '\.evtx$'
    mkdir-quiet $zipDirectoryName

    # Move .evtx file inside same-name directory.
    # The only built-in, .NET method for zip compression requires a directory.
    Move-Item $ArchivedLogs[$i].Path $zipDirectoryName -ea stop

    # Verify the previous file move before compression
    if (Test-Path (Join-Path $zipDirectoryName (Split-Path $ArchivedLogs[$i].Path -Leaf))) {

        # Set up path variables for zip destination
        $fileBaseName = Split-Path $zipDirectoryName -Leaf
        $zipFullName = Join-Path $DestYearDir "$fileBaseName.zip"
        [System.IO.Compression.ZipFile]::CreateFromDirectory($zipDirectoryName, $zipFullName)

        # Verify that the created file is not zero bytes (presumably would indicate a successful compression).
        $test = Get-Item $zipFullName
        if (-Not ($test -and ($test.Length -gt 0))) {

            # Since something went wrong with creating the zip file, undo all previous file moves
            Write-Error "Error creating compressed folder."
            Move-Item (Join-Path $zipDirectoryName (Split-Path $ArchivedLogs[$i].Path -Leaf)) $ArchivedLogs[$i].Path
        }
    }

    # Clean up temp directory
    Remove-Item $zipDirectoryName -Recurse
   
}