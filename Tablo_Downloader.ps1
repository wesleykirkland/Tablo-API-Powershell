<#To Do
Exceptions Lists
Show Air Date Exceptions List
Delete Function(s)
Add support for mounted paths to Disk space check function
Supress FFMPEG and find a native PowerShell wrapper for it if I can, or build a static function out of it
Alerting for conflicts - can check series conflicts on /guide/series/$SeriesID
Add support for movies, sports, series, programs - Framework setup for this, TV is done
Build configuration function which sets $TabloAPIBaseURL, easy peazy
#>

#Requires
#Requres -module Tablo_API

$SQLServerInstance = 'SQLPDB01.lan.local'
$SQLServerDatabase = 'TabloV2'

Write-Verbose 'Testing for SQL Connection'
Try {
    Test-MSSQLConnection -ServerInstance $SQLServerInstance
} Catch {
    Write-Error "Unable to connect to $($SQLServerInstance), exiting now"
    exit
}

#Establish a SQL Connection
$SQLConnection = New-MSSQLConnection -ServerInstance $SQLServerInstance -Database $SQLServerDatabase

#Export the config from the DB and convert it to a HashTable via Get-TabloConfig
$ConfigValues = Get-TabloConfig -ConfigValues (Invoke-MSSQLQuery -SQLConnection $SQLConnection -Query "SELECT ConfigKey,ConfigValue FROM Configuration")

#Set the base TabloUrl to the Global Scope for Invoke-TabloAPIRequest
$Global:TabloAPIBaseURL = "http://$($ConfigValues['TabloFQDN']):$($ConfigValues['TabloAPIPort'])"

#Splatting for the notification System
$SplatSlack = @{
    'SlackNotifications' = [boolean]$ConfigValues['SlackNotifications']
    'SlackWebHookUrl' = $ConfigValues['SlackWebHookURL']
    'SlackChannel' = $ConfigValues['SlackChannel']
}

$SplatSMTP = @{
    'SMTPNotifications' = [boolean]$ConfigValues['SMTPNotifications']
    'SMTPServer' = $ConfigValues['SMTPServer']
    'SMTPTo' = $ConfigValues['SMTPTo']
    'SMTPFrom' = $ConfigValues['SMTPFrom']
}

#Define Notification Types, find what types we should notify on and then each notification will run through the loop
[System.Collections.ArrayList]$NotificationTypes = @()
foreach ($Type in ($ConfigValues.Keys | Where-Object {($PSItem -like '*Notifications')})) { #See if we should notify these ways
    if ($ConfigValues["$Type"] -eq $true) {
        [void]$NotificationTypes.Add(
            [pscustomobject]@{
                'Type' = $Type;
                'SplatConfig' = switch ($Type) {
                    'SlackNotifications' {$SplatSlack}
                    'SMTPNotifications' {$SplatSMTP}
                }
            }
        )
    }
}

Write-Verbose 'Checking to see if FFMPeg is installed'
if (!(Test-Path -Path $ConfigValues['FFMPEGBinary'])) {
    Write-Error -Message "Unable to locate FFMPEG Binary, please correct the path"
    exit
}

Write-Verbose 'Checking to see if our Temp Download Path(s) exists, and check disk space on those location'
[System.Collections.ArrayList]$NotificationTypes = @()
foreach ($Type in ($ConfigValues.Keys | Where-Object {($PSItem -like 'DownloadLocation*')})) { #See if we should notify these ways
    if (!(Test-Path -Path $ConfigValues[$Type])) {
        Try {
            New-Item -Path $ConfigValues[$Type] -ItemType dir
        } Catch {
            Write-Error -Message "Unable to make temp directory $($ConfigValues[$Type]), please check your filesystem"
            Write-Verbose 'Sending notifications'
            $NotificationTypes | ForEach-Object {
                $TempSplat = $PSItem.SplatConfig
                Send-TabloNotification @TempSplat -Message "Unable to make temp directory $($ConfigValues[$Type]), please check your filesystem"
                Remove-Variable TempSplat -ErrorAction SilentlyContinue
            }
            exit
        }
    }

    #Need to make this accept mount paths and UNC paths as well
    Try {
        Test-MinimumFreeDiskSpace -DiskDrive $($ConfigValues[$Type].split(':')[0]) -DiskMinimumFreePercentage $($ConfigValues['DiskMinimumFreePercentage'])
    } Catch {
        Write-Warning 'Not enough disk space, exiting'
        $NotificationTypes | ForEach-Object {
            $TempSplat = $PSItem.SplatConfig
            Send-TabloNotification @TempSplat -Message 'Not enough disk space, exiting'
            Remove-Variable TempSplat -ErrorAction SilentlyContinue
        }
        exit
    }
}

Write-Verbose 'Testing for ping'
if ((Test-TabloConnection -TabloFQDN $ConfigValues['TabloFQDN']).ping) {
    Write-Verbose 'Getting Tablo Recordings'
    $TabloAirings = Get-TabloAirings

    Foreach ($Recording in $TabloAirings) {
        Write-Verbose 'Checking for disk space before we continue'
        Try {
            Test-MinimumFreeDiskSpace -DiskDrive $($ConfigValues['DownloadLocationSeries'].split(':')[0]) -DiskMinimumFreePercentage $($ConfigValues['DiskMinimumFreePercentage'])
        } Catch {
            Write-Warning 'Not enough disk space, exiting'
            break
        }

        #Get the metatdata of the Recording
        switch ($Recording.Type) {
            'series' {
                $RecIDMetaData = Get-TabloEpisodeMetaData -RecID $Recording.RecID
                $SeriesIDMetaData = Get-TabloSeriesMetaData -SeriesID $($RecIDMetaData.series_path.split('/')[-1])
                $ShowName = Convert-CommonCharacterEscaping -string $SeriesIDMetaData.series.title;
                if (
                    !(
                        ($RecIDMetaData.episode.season_number -eq 0) -and
                        ($RecIDMetaData.episode.number -eq 0)
                    )
                ) {
                    $FileName = "$($ShowName)-S$($RecIDMetaData.episode.season_number)E$($RecIDMetaData.episode.number)"
                } else {
                    $FileName = Convert-CommonCharacterEscaping -string $ShowName -Unescape
                }
            }
            'movies' {} #TBD
            'sports' {} #TBD
            'programs' {} #TBD
        }

        #Checking to see if we have already downloaded this show
        $SQLRecordingsSelect = Invoke-MSSQLQuery -SQLConnection $SQLConnection -Query "SELECT Recid,Processed,Warnings FROM Recordings where RECID = $($Recording.RecID)"

        #Check to see if we need to process the show
        if (
            (([string]::IsNullOrWhiteSpace($SQLRecordingsSelect.RecID)) -or ([string]::IsNullOrWhiteSpace($SQLRecordingsSelect.Processed))) -and #Make sure the RecID is null and processed has not been set
            (!($SQLRecordingsSelect.Warnings)) -and
            ($RecIDMetaData.video_details.state -eq 'finished') #See if the recording status is finished, recording support will come later
        ) {
            #Build the RecIDEntry beforehand as it's needed in the if and else statement. DB Object Entry, 100% dynamic
            Try {
                $RecIDEntry = [PSCustomObject]@{
                    'AirDate' = $RecIDMetaData.airing_details.datetime | Get-Date -Format 'yyyy-MM-dd';
                    'Description' = Convert-CommonCharacterEscaping -string $RecIDMetaData.episode.Description;
                    'EpisodeName' = if ($RecIDMetaData.episode.title) {Convert-CommonCharacterEscaping -string $RecIDMetaData.episode.title} else {Convert-CommonCharacterEscaping -string $RecIDMetaData.airing_details.show_title};
                    'EpisodeNumber' = $RecIDMetaData.episode.number;
                    'EpisodeSeason' = $RecIDMetaData.episode.season_number;
                    'FileName' = $FileName;
                    'Media' = $Recording.Type;
                    'PostProcessDate' = Get-Date -Format 'yyyy-MM-dd';
                    'RecID' = $Recording.RecID;
                    'Show' = $ShowName;
                    'Warnings' = if ([string]::IsNullOrWhiteSpace($RecIDMetaData.video_details.warnings)) {$null} else {$RecIDMetaData.video_details.warnings};
                }
            } Catch {
                $Error[0]
                break
            }

            #Build out our SQL Insert query, it's needed in the if statement and else statement
            $SQLInsertColumns = ($RecIDEntry | Get-Member -MemberType NoteProperty).Name | Sort-Object
                [System.Collections.ArrayList]$SQLInsert = @()
                [void]$SQLInsert.Add("INSERT INTO Recordings ($($SQLInsertColumns -join ',')) VALUES (")

                [System.Collections.ArrayList]$SQLInsertValues = @()
                foreach ($Column in $SQLInsertColumns) {
                    [void]$SQLInsertValues.Add(("'$($RecIDEntry.$Column)'"))
                }

                [void]$SQLInsert.Add("$($SQLInsertValues -join ','))")

            #Make sure there are not episode warings
            if (!($RecIDMetaData.video_details.warnings)) {
                #If series add the Show to the Shows DB table
                if ($Recording.Type -eq 'series') {
                    Write-Verbose "Checking to see if $($ShowName) is in the db"
                    if (!(Invoke-MSSQLQuery -SQLConnection $SQLConnection -Query "SELECT Title FROM TV_Shows WHERE Title = '$($ShowName)'")) {
                        Try {
                            Invoke-MSSQLQuery -SQLConnection $SQLConnection -Query "INSERT INTO TV_Shows (Title,Description,Orig_air_Date) VALUES ('$($RecIDEntry.Show)','$(Convert-CommonCharacterEscaping -string $SeriesIDMetaData.series.description)','$($SeriesIDMetaData.series.orig_air_date)')"
                        } Catch {
                            Write-Verbose 'Sending notifications'
                            $NotificationTypes | ForEach-Object {
                                $TempSplat = $PSItem.SplatConfig
                                Send-TabloNotification @TempSplat -Message "Failed to add $ShowName to TV_Shows Table"
                                Remove-Variable TempSplat -ErrorAction SilentlyContinue
                            }
                        }
                    } #End if Show exists in DB Check
                }

                Write-Verbose "Inserting RecID $($Recording.RecID) into the DB"
                Try {
                    Invoke-MSSQLQuery -SQLConnection $SQLConnection -Query $SQLInsert
                } Catch {
                    Write-Verbose 'Sending notifications'
                    $NotificationTypes | ForEach-Object {
                        $TempSplat = $PSItem.SplatConfig
                        Send-TabloNotification @TempSplat -Message "Failed to add $($Recording.RecID) to Recordings Table, SQL Query: $($SQLInsert)"
                        Remove-Variable TempSplat -ErrorAction SilentlyContinue
                    }
                }

                if ($RecIDMetaData.video_details.state -eq 'finished') {
                    Write-Verbose "Downloading $($Recording.RecID)"
                    Invoke-TabloRecordingDownload -RecID $Recording.RecID -FileName $RecIDEntry.FileName -DownloadLocation $ConfigValues["DownloadLocation$($RecIDEntry.Media)"] -FFMPEGBinary $ConfigValues['FFMPEGBinary'] -TabloFQDN $ConfigValues['TabloFQDN']
                
                    Write-Verbose "Update SQL with recording as processed"
                    Try {
                        Invoke-MSSQLQuery -SQLConnection $SQLConnection -Query "UPDATE Recordings SET Processed = 1 WHERE RecID = $($Recording.RecID)"

                        if ($?) {
                            Write-Verbose 'Sending notifications'
                            $NotificationTypes | ForEach-Object {
                                $TempSplat = $PSItem.SplatConfig
                                Send-TabloNotification @TempSplat -Message "Successfully downloaded RecID $($Recording.RecID) - $($RecIDEntry.FileName)"
                                Remove-Variable TempSplat -ErrorAction SilentlyContinue
                            }
                        }
                    } Catch {
                        Write-Verbose 'Sending notifications'
                        $NotificationTypes | ForEach-Object {
                            $TempSplat = $PSItem.SplatConfig
                            Send-TabloNotification @TempSplat -Message "Failed to update $($Recording.RecID) to Processed in Recordings Table"
                            Remove-Variable TempSplat -ErrorAction SilentlyContinue
                        } #End foreach on NotificationTypes
                    } #End Try Catch on marking recording as Processed
                } #End if on $RecIDMetaData.video_details.state
            } else {
                Write-Warning "$($Recording.RecID) has warnings $($RecIDEntry.Warnings), I will delete it and log it"
                Invoke-MSSQLQuery -SQLConnection $SQLConnection -Query $SQLInsert

                Write-Verbose 'Sending notifications'
                $NotificationTypes | ForEach-Object {
                    $TempSplat = $PSItem.SplatConfig
                    Send-TabloNotification @TempSplat -Message "RecID $($Recording.RecID) $($RecIdEntry.FileName) has recording errors: $($RecIDEntry.Warnings)"
                    Remove-Variable TempSplat -ErrorAction SilentlyContinue
                }

                #Delete the recording from the Tablo as it's jank
                Remove-TabloRecording -RecID $Recording.RecID -AiringType $RecIDEntry.media 
            } #End else statement if RecID has warning
        } #End if statement to check for video wanrings
        Try {
            Remove-Variable RecIDEntry,ShowName,FileName -ErrorAction SilentlyContinue
        } Catch {
            $Error.RemoveAt(0)
        }
    } #End foreach Recording in TabloAirings
} else {
    Write-Error "Unable to ping $($ConfigValues['TabloFQDN']), exiting now"
    exit
}