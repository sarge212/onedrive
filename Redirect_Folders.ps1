<#
.SYNOPSIS
    Sets a known folder's path using SHSetKnownFolderPath.
.PARAMETER KnownFolder
    The known folder whose path to set.
.PARAMETER Path
    The target path to redirect the folder to.
.NOTES
    Forked from: https://gist.github.com/semenko/49a28675e4aae5c8be49b83960877ac5
#>
Function Set-KnownFolderPath {
    Param (
            [Parameter(Mandatory = $true)]
            [ValidateSet( 'Desktop', 'Documents', 'Downloads', 'Favorites', 'Music','Pictures','Videos',)]
            [string]$KnownFolder,

            [Parameter(Mandatory = $true)]
            [string]$Path
    )

    # Define known folder GUIDs
    $KnownFolders = @{
        'Desktop' = @('B4BFCC3A-DB2C-424C-B029-7FE99A87C641');
        'Documents' = @('FDD39AD0-238F-46AF-ADB4-6C85480369C7','f42ee2d3-909f-4907-8871-4c22fc0bf756');
        'Downloads' = @('374DE290-123F-4565-9164-39C4925E467B','7d83ee9b-2244-4e70-b1f5-5393042af1e4');
        'Favorites' = @('1777F761-68AD-4D8A-87BD-30B759FA33DD');
        'Music' = @('4BD8D571-6D19-48D3-BE97-422220080E43','a0c69a99-21c8-4671-8703-7934162fcf1d');
        'Pictures' = @('33E28130-4E1E-4676-835A-98395C3BC3BB','0ddd015d-b06c-45d5-8c4c-f59713854639');
        'Videos' = @('18989B1D-99B5-455B-841C-AB7C74E4DDFC','35286a68-3c57-41a1-bbb1-0eae73d76c95');
    }

    # Define SHSetKnownFolderPath if it hasn't been defined already
    $Type = ([System.Management.Automation.PSTypeName]'KnownFolders').Type
    If (-not $Type) {
        $Signature = @'
[DllImport("shell32.dll")]
public extern static int SHSetKnownFolderPath(ref Guid folderId, uint flags, IntPtr token, [MarshalAs(UnmanagedType.LPWStr)] string path);
'@
        $Type = Add-Type -MemberDefinition $Signature -Name 'KnownFolders' -Namespace 'SHSetKnownFolderPath' -PassThru
    }

	# Make path, if doesn't exist
	If (!(Test-Path $Path -PathType Container)) {
		New-Item -Path $Path -Type Directory -Force
    }

    # Validate the path
    If (Test-Path $Path -PathType Container) {
        # Call SHSetKnownFolderPath
        #  return $Type::SHSetKnownFolderPath([ref]$KnownFolders[$KnownFolder], 0, 0, $Path)
        ForEach ($guid in $KnownFolders[$KnownFolder]) {
            $result = $Type::SHSetKnownFolderPath([ref]$guid, 0, 0, $Path)
            If ($result -ne 0) {
                $errormsg = "Error redirecting $($KnownFolder). Return code $($result) = $((New-Object System.ComponentModel.Win32Exception($result)).message)"
                Throw $errormsg
            }
        }
    } Else {
        Throw New-Object System.IO.DirectoryNotFoundException "Could not find part of the path $Path."
    }
	
	# Fix up permissions, if we're still here
	Attrib +r $Path
    
    Return $Path
}

<#
.SYNOPSIS
    Gets a known folder's path using GetFolderPath.
.PARAMETER KnownFolder
    The known folder whose path to get.
.NOTES
    https://stackoverflow.com/questions/16658015/how-can-i-use-powershell-to-call-shgetknownfolderpath
#>
Function Get-KnownFolderPath {
    Param (
            [Parameter(Mandatory = $true)]
            [ValidateSet( 'Desktop', 'Documents', 'Downloads', 'Favorites', 'Music','Pictures','Videos',)]
            [string]$KnownFolder
    )

    Return [Environment]::GetFolderPath($KnownFolder)
}

<#
.SYNOPSIS
    Moves contents of a folder with output to a log.
    Uses Robocopy to ensure data integrity and all moves are logged for auditing.
    Means we don't need to re-write functionality in PowerShell.
.PARAMETER Source
    The source folder.
.PARAMETER Destination
    The destination log.
.PARAMETER Log
    The log file to store progress/output
#>
Function Move-Files {
    Param (
            [Parameter(Mandatory = $true)]
            [string]$Source,

            [Parameter(Mandatory = $true)]
            [string]$Destination,

            [Parameter(Mandatory = $true)]
            [string]$Log
    )

    If (!(Test-Path (Split-Path $Log))) { New-Item -Path (Split-Path $Log) -ItemType Container }
    Robocopy.exe $Source $Destination /E /MOV /XJ /R:1 /W:1 /NP /LOG+:$Log
}

<#
.SYNOPSIS
    Function exists to reduce code required to redirect each folder.
#>
Function Redirect-Folder {
    Param (
        $SyncFolder,
        $GetFolder,
        $SetFolder,
        $Target
    )

    # Get current Known folder path
    $Folder = Get-KnownFolderPath -KnownFolder $GetFolder

    # If paths don't match, redirect the folder
    If ($Folder -ne "$SyncFolder\$Target") {
        # Redirect the folder
        Set-KnownFolderPath -KnownFolder $SetFolder -Path "$SyncFolder\$Target"
        # Move files/folders into the redirected folder
        Move-Files -Source $Folder -Destination "$SyncFolder\$Target" -Log "$env:LocalAppData\RedirectLogs\Robocopy$Target.log"
        # Hide the source folder (rather than delete it)
        Attrib +h $Folder
    }    
}

# Get OneDrive sync folder
$OneDriveFolder = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1' -Name 'UserFolder'

# Redirect select folders
If (Test-Path $OneDriveFolder) {
    
    Redirect-Folder -SyncFolder $OneDriveFolder -GetFolder 'Desktop' -SetFolder 'Desktop' -Target 'Desktop'
    Redirect-Folder -SyncFolder $OneDriveFolder -GetFolder 'MyDocuments' -SetFolder 'Documents' -Target 'Documents'
    Redirect-Folder -SyncFolder $OneDriveFolder -GetFolder 'MyPictures' -SetFolder 'Pictures' -Target 'Pictures'
    Redirect-Folder -SyncFolder $OneDriveFolder -GetFolder 'Videos' -SetFolder 'Videos' -Target 'Videos'
    Redirect-Folder -SyncFolder $OneDriveFolder -GetFolder 'Downloads' -SetFolder 'Downloads' -Target 'Downloads'
    Redirect-Folder -SyncFolder $OneDriveFolder -GetFolder 'Music' -SetFolder 'Downloads' -Target 'Music'

} 