#Global Variables
$Tablo = "tablo.domain.tld"
$TempDownload = "D:\Tablo"
$TabloRecordingURI = ("http://"+$Tablo+":18080/plex/rec_ids")
$TabloPVRURI = ("http://"+$Tablo+":18080/pvr/")
$FFMPEGBinary = "C:\ffmpeg\bin\ffmpeg.exe"
$DumpDirectoryDriveLetter = 'D' #Replace this with the drive letter for your dump directories
$DumpDirectoryTV = "$($DumpDirectoryDriveLetter):\Tablo\Processed_TV"
$DumpDirectoryMovies = "$($DumpDirectoryDriveLetter):\Tablo\Processed_Movies"
$DumpDirectoryExceptions = "\\fileserver\torrent\Downloaded Torrents" #File path for $ShowExceptionsList
$SickRageAPIKey = 'apikey'
$SickRageURL = 'https://SickRageorSickBeard:8081' #No Trailing '/'
$EnableSickRageSupport = $true
$EmailTo = 'person@domain.tld'
$EmailFrom = ($env:COMPUTERNAME + "@domain.tld")
$EmailSMTP = 'smtp.domain.tld'
$MinimumFreePercentage = 10 #Put a number here between 1-100 and it will be calculated down into a percentage
$SlackNotifications = $true
$EmailNotifications = $false
#TVDB Variables
$TVDBAPIKey = 'APIKEY'
$TVDBUserKey = 'UserKey' #https://api.thetvdb.com/swagger
$TVDBBaseURI = 'https://api.thetvdb.com' #https://api.thetvdb.com/swagger
#Slack Variables
$SlackChannel = 'media_notifications'
$SlackWebHookUrl = 'https://hooks.slack.com'

#SQL Variables
$ServerInstance = "SQLPDB01"
$Database = "Tablo"

#Splatting Configs
$MailConfig = @{
    ErrorAction = 'STOP'
    From        = $EmailFrom
    SmtpServer  = $EmailSMTP
    To          = $EmailTo
}

$RestConfigGet = @{
    ErrorAction = 'STOP'
    Method      = 'Get'
}

$RestConfigPost = @{
    ErrorAction = 'STOP'
    Method      = 'Post'
}

$SQLConfig = @{
    ServerInstance = $ServerInstance
    Database = $Database
}

$SlackConfig = @{
    SlackWebHook = $SlackWebHookUrl
    SlackChannel = $SlackChannel
}

#region Function
#Functions
#Test SQL Server Connection
Function Test-SQLConnection {
    #Params
    [CmdletBinding()]
    Param(
    [parameter(Position=0,Mandatory=$true)]
        $ServerInstance,
    [parameter()]
        [System.Management.Automation.PSCredential]$Cred,
    [parameter()]
        [switch]$NoSSPI = $false
    )

    Process {
        if ($NoSSPI -and (!($Cred))) {
            $Cred = Get-Credential
        }

        if ($NoSSPI) {
            Write-Verbose 'Setting SQL to use local credentials'
            $connectionString = "Data Source = $ServerInstance;Initial Catalog=master;User ID = $($cred.UserName);Password = $($cred.GetNetworkCredential().password);"
        } else {
            Write-Verbose 'Setting SQL to use SSPI'
            $connectionString = "Data Source=$ServerInstance;Integrated Security=true;Initial Catalog=master;Connect Timeout=3;"
        }

        $sqlConn = New-Object ("Data.SqlClient.SqlConnection") $connectionString
        trap {
            Write-Error "Cannot connect to $Server.";
            exit
        }

        $sqlConn.Open()
        if ($sqlConn.State -eq 'Open') {
            Write-Verbose "Successfully connected to $ServerInstance"
            $sqlConn.Close()
        }
    }
}

Function Run-SQLQuery {
    #Params
    [CmdletBinding()]
    Param(
    [parameter(Position=0,Mandatory=$true)]
        $ServerInstance,
    [parameter(Position=1,Mandatory=$true)]
        $Query,
    [parameter(Position=2,Mandatory=$true)]
        $Database,
    [parameter()]
        [System.Management.Automation.PSCredential]$Cred,
    [parameter()]
        [switch]$NoSSPI = $false
    )

    Process {
        if ($NoSSPI -and (!($Cred))) {
            $Cred = Get-Credential
        }

        #Open SQL Connection
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection 
        if ($NoSSPI) {
            Write-Verbose 'Setting SQL to use local credentials'
            $SqlConnection.ConnectionString = "Server = $ServerInstance;Database=$Database;User ID=$($cred.UserName);Password=$($cred.GetNetworkCredential().password);"   
        } else {
            Write-Verbose 'Setting SQL to use SSPI'
            $SqlConnection.ConnectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=True"
        }

        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand 
        $SqlCmd.Connection = $SqlConnection 
        $SqlCmd.CommandText = $Query 
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter 
        $SqlAdapter.SelectCommand = $SqlCmd 
        $DataSet = New-Object System.Data.DataSet 
        $a = $SqlAdapter.Fill($DataSet) 
        $SqlConnection.Close() 
        $DataSet.Tables[0]
    }
}

#Function to get metadata associated with a recording
function Get-TabloRecordingMetaData ($Recording) {
    $MetadataURI = $TabloPVRURI + $Recording + "/meta.txt"
    $JSONMetaData = Invoke-RestMethod @RestConfigGet -Uri $MetadataURI

    Write-Verbose "Check if metadata is present"
    if (!($?)) {
        $Script:NoMetaData = $false
    }

    Write-Verbose "Check to see if we are processing a Movie or a TV Show"
    if ($JSONMetaData.recEpisode) {
        Write-Verbose "A TV Show was detected"
        #Build Variables and Episode Data for later processes
        $Script:ShowName = $JSONMetaData.recSeries.jsonForClient.title #Get Show Title
        $Script:EpisodeDescription = $JSONMetaData.recepisode.jsonForClient.description #Get Episode Description
        $Script:EpisodeOriginalAirDate = $JSONMetaData.recepisode.jsonForClient.originalAirDate #Get Air Date
        $Script:EpisodeName = $JSONMetaData.recepisode.jsonForClient.title #Get Episode Title
        $Script:EpisodeSeason = $JSONMetaData.recEpisode.jsonForClient.seasonNumber #Get Episode Season
        $Script:EpisodeNumber = $JSONMetaData.recEpisode.jsonForClient.episodenumber #Get Episode Number
        $Script:EpisodeWarnings = $JSONMetaData.recEpisode.jsonForClient.video.warnings #Episode Duration
        $Script:RecIsFinished = $JSONMetaData.recepisode.jsonForClient.video.state #Check if Recording is finished

        #Character Replacement as some Characters Piss off FFMPEG, Create File Name
        $FileName = $ShowName + "-S" +$EpisodeSeason + "E" + $EpisodeNumber
        $Script:FileName = [string]$FileName.Replace(":","")

        #Character Replacement as some Characters Piss off FFMPEG, Create File Name as AirDate
        $ModifiedAirDate = ($EpisodeOriginalAirDate).Split("-")
        $ModifiedAirDate = $ModifiedAirDate[1] + '.' + $ModifiedAirDate[2] + '.' + $ModifiedAirDate[0]
        $FileName = $ShowName + " " + $ModifiedAirDate
        $Script:FileNameAirDate = [string]$FileName.Replace(":","").Replace("-",".")

        $Script:MediaType = 'TV' #Set the Media Type to a TV Show
    } elseif ($JSONMetaData.recMovie) {
        Write-Verbose "A Movie was detected"
        $Script:RecIsFinished = $JSONMetaData.recMovieAiring.jsonForClient.video.state #Check if Recording is finished
        $Script:ReleaseYear = $JSONMetaData.recMovieAiring.jsonFromTribune.program.releaseYear #Get Release Year
        $Script:MovieName =  $JSONMetaData.recMovieAiring.jsonFromTribune.program.title #Get Episode Title
        
        Write-Verbose "Character replacement as some Characters Piss off FFMPEG, Creating the File Name"
        $FileName = $MovieName + " (" +$ReleaseYear + ")"
        $Script:FileName = [string]$FileName.Replace(":","")

        $Script:MediaType = 'MOVIE' #Set the Media Type to a Movie
    }
}

#Function to checkif the file we are going to create already exists and if so append a timestamp
function Check-ForDuplicateFile ($Directory,$FileName) {
    if (Test-Path -Path "$Directory\$FileName") {
        $Script:FileName = $FileName + '-' + (Get-Date -Format yyyy-MM-dd_HH-mm)
    } #Else do nothing and leave the file name alone.
}

#Function to get Series Information from the TVDB by Series ID
function Get-TVDBSeriesInformationByID ($ShowID,$TVDBAPIKey,$TVDBUserKey) {
    #Build our TVDBHeaders
    $TVDBHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $TVDBHeaders.Add('Accept', 'application/json')
    $TVDBHeaders.Add('Content-Type', 'application/json')

    #JSON to Authenicate to the TVDB
    $TVDBJSONLogin = ConvertTo-Json(@{
        apikey = $TVDBAPIKey;
        userkey = $TVDBUserKey;
    })

    #Login to the TVDB API and get our Bearer Token
    $TVDBToken = (Invoke-RestMethod @RestConfigPost -Uri "$TVDBBaseURI/login" -Body $TVDBJSONLogin -Headers $TVDBHeaders).Token

    #Add our OAuth Token to our Header
    $TVDBHeaders.Add('Authorization', "Bearer $TVDBToken")

    #Find the ShowName
    (Invoke-RestMethod @RestConfigGet -Uri "$TVDBBaseURI/series/$ShowID" -Headers $TVDBHeaders).Data
}

#Function to get information from the Open Movie Database, thank god I don't actually have to authenticate here
function Get-OpenMovieDataBaseByID ($IMDBId) {
    (Invoke-RestMethod @RestConfigGet -Uri "http://www.omdbapi.com/?i=$($IMDBId)&plot=short&r=json")
}

#Function to auto add new shows to SickRage
Function Add-ToSickRage ($ShowName,$SickRageAPIKey,$SickRageURL) {
    #Find the TVDB ID
    Try {
        $TVDBResults = Invoke-RestMethod @RestConfigGet -Uri "$SickRageURL/api/$SickRageAPIKey/?cmd=sb.searchtvdb&name=$ShowName"
    } Catch [System.Net.WebException] {
        if ($EmailNotifications) {
            Send-MailMessage @MailConfig -Subject 'An Error occured while calling the SickRage API'
        }

        if ($SlackNotifications) {
            Send-SlackNotification @SlackConfig -Message 'An Error occured while calling the SickRage API'
        }
    }
 
    #Verify we successfully ran the query, and atleast 1 or more data results as well as the result is in english
    If (($TVDBResults.result -eq 'success') -and ($TVDBResults.data.results.name -ge 1) -and ($TVDBResults.data.langid -eq 7)) {
        #Select the correct results based upon the most recent show
        $TVDBObjects = $TVDBResults.data.results | Where-Object {($PSItem.first_aired -notlike 'Unknown')} | Sort-Object first_aired -Descending

        #If only 1 entry was returned it is useless to continue the logic so we will go with it, else we will loop through some logic
        if ($TVDBObjects.Count -eq 1) {
            #Add the show to SickRage
            Write-Verbose "Added $($TVDBObjects.tvdbid) - $($TVDBObjects.Name) to SickRage as it was the only valid entry"
            Invoke-RestMethod @RestConfigGet -Uri "$SickRageURL/api/$SickRageAPIKey/?cmd=show.addnew&future_status=skipped&lang=en&tvdbid=$($TVDBObjects.tvdbid)"
        } else {
            foreach ($TVDBObject in $TVDBObjects) {
                Write-Host "Working on $($TVDBObject.tvdbid)"
                #Compare the dates to see if this is an accurate listing
                $IMDBID = (Get-TVDBSeriesInformationByID -ShowID $TVDBObject.tvdbid -TVDBAPIKey $TVDBAPIKey -TVDBUserKey $TVDBUserKey).imdbid
                $OMDBEntry = Get-OpenMovieDataBaseByID -IMDBId $IMDBID

                #Check to make sure we got a valid response from IMDB/OMDB
                if ($OMDBEntry.Response -notlike $false) {
                    #Split the years of the IMDB/OMDB Entry
                    $OMDBYears = $OMDBEntry.Year.Split('–') | Where-Object {($PSItem -notlike $null)}
                    #If a show if new we can only check if the air date is newer or equal to what IMDB/OMDB tells us our series run time is, if not we will continue below
                    if ($OMDBYears.Count -eq 1) {
                        Write-Verbose "OMDBYears has only one entry, we will now test that date against EpisodeOriginalAirDate"
                        $OMDBEpisodeOriginalAirDateYYYY = ($EpisodeOriginalAirDate | Get-Date -Format 'yyyy')
                        if ($OMDBYears -ge $OMDBEpisodeOriginalAirDateYYYY) {
                            $ShowIDInformation = New-Object PSObject -Property @{
                                ShowName = $ShowName
                                IMDBID = $IMDBID
                                TVDBID = $TVDBObject.tvdbid
                                YearsRunTime = $OMDBEntry.Year.Split('–')[0]
                                WithinYearRunTime = $true
                            }
                            Write-Verbose "We have successfully verified the EpisodeOriginalAirDate against IMDB/OMDB, keeping this in memory for later"
                        }
                    } else {
                        Write-Verbose "OMDBYears had more than 1 date, we will test the logic now"
                        #See if we are within the date range of our air date and what IMDB/OMDB tells us our series run time is
                        if (($OMDBYears[0] -ge $OMDBEpisodeOriginalAirDateYYYY) -and ($OMDBEpisodeOriginalAirDateYYYY -le $OMDBYears[-1])) {
                            $ShowIDInformation = New-Object PSObject -Property @{
                                ShowName = $ShowName
                                IMDBID = $IMDBID
                                TVDBID = $TVDBObject.tvdbid
                                YearsRunTime = $OMDBEntry.Year
                                WithinYearRunTime = $true
                            }
                            Write-Verbose "We were able to successfully verify that EpisodeOriginalAirDate Matches IMDB/OMDB"
                        } else {
                            $ShowIDInformation = New-Object PSObject -Property @{
                                ShowName = $ShowName
                                IMDBID = $IMDBID
                                TVDBID = $TVDBObject.tvdbid
                                YearsRunTime = $OMDBEntry.Year
                                WithinYearRunTime = $false
                            }
                            Write-Verbose "Unable to verify that EpisodeOriginalAirDate Matches IMDB/OMDB"
                        }
                    }
                    #Check if our logic statements above said we are good to go!
                    if ($ShowIDInformation.WithinYearRunTime) {
                        #Add the show to SickRage
                        Invoke-RestMethod @RestConfigGet -Uri "$SickRageURL/api/$SickRageAPIKey/?cmd=show.addnew&future_status=skipped&lang=en&tvdbid=$($TVDBObject.tvdbid)"
                        Write-Host "We would add $($TVDBObject.tvdbid) to sickrage"
                    }
                } #End of if Statement for Response validity
            } #End foreach loop
        } #End TVDBObjects Count
        
        #Send a notification of the Show we added to SickRage        
        if ($EmailNotifications) {
            Send-MailMessage @MailConfig -Subject "New Show '$($TVDBObject.name)' Auto added to SickRage"
        }

        if ($SlackNotifications) {
            Send-SlackNotification @SlackConfig -Message "New Show '$($TVDBObject.name)' Auto added to SickRage"
        }
    }
}

#Function to recheck the episodes recording status
function Get-TabloRecordingStatus ($Recording) {
    $MetadataURI = $TabloPVRURI + $Recording + "/meta.txt"
    $JSONMetaData = Invoke-RestMethod @RestConfigGet -Uri $MetadataURI

    Write-Verbose "Check if metadata is present"
    if (!($?)) {
        $Script:NoMetaData = $false
    }

    Write-Verbose "Check to see if we are processing a Movie or a TV Show, and then set the RecIsFinished variable"
    if ($JSONMetaData.recEpisode) {
        $Script:RecIsFinished = $JSONMetaData.recepisode.jsonForClient.video.state
    }
    elseif ($JSONMetaData.recMovie) {
        $Script:RecIsFinished = $JSONMetaData.recMovieAiring.jsonForClient.video.state
    }
}

#Function to send notifications to slack
function Send-SlackNotification {
    # ----------------------------------------------------------------------------------------------
    # Copyright (c) WCOM AB 2016.
    # ----------------------------------------------------------------------------------------------
    # This source code is subject to terms and conditions of the The MIT License (MIT)
    # copy of the license can be found in the LICENSE file at the root of this distribution.
    # ----------------------------------------------------------------------------------------------
    # You must not remove this notice, or any other, from this software.
    # ----------------------------------------------------------------------------------------------
    Param(
        [string]$SlackWebHook,
        [string]$SlackChannel,
        [string]$Message
    )

    Add-Type -AssemblyName System.Web.Extensions

    $postSlackMessage = ConvertTo-Json(
        @{
            channel      = $SlackChannel;
            unfurl_links = "true";
            username     = "Tablo API";
            icon_url     = "https://www.rokuchannels.tv/wp-content/uploads/2015/02/tablotv.jpg"
            text         = "$Message";
        }
    )

    [System.Net.WebClient] $webclient = New-Object 'System.Net.WebClient'
    $webclient.UploadData($SlackWebHook, [System.Text.Encoding]::UTF8.GetBytes($postSlackMessage))
}
#endregion

##########################################################################################################################################################################################################################################################################################################################
Write-Verbose "Pinging the Tablo and checking for directories"
if (!(Test-Connection -ComputerName $Tablo -Count 1)) {
    Write-Warning "Unable to ping the tablo, please investigate this"
    exit
}
if (!(Test-Path -Path $FFMPEGBinary)) {
    Write-Warning "Unable to locate FFMPEG Binary, please correct the path"
    exit
}
if (!(Test-Path -Path $TempDownload)) {
    New-Item -Path $TempDownload -ItemType dir
}
if (!(Test-Path -Path $DumpDirectoryTV)) {
    New-Item -Path $DumpDirectoryTV -ItemType dir
}
if (!(Test-Path -Path $DumpDirectoryMovies)) {
    New-Item -Path $DumpDirectoryMovies -ItemType dir
}

Write-Verbose 'Checking for a minimum disk space before continuing'
$DriveObject = Get-WmiObject Win32_LogicalDisk | Where-Object {($PSItem.DeviceID -eq "$($DumpDirectoryDriveLetter):")}
#Find the minimum free bytes
if ($DriveObject.FreeSpace -lt ($DriveObject.Size * (".$MinimumFreePercentage"))) {
    Write-Warning "Drive $DumpDirectoryDriveLetter has less than $($MinimumFreePercentage)% free, we will exit the script until this is resolved"
    if ($EmailNotifications) {
        Send-MailMessage @MailConfig -Subject "Drive $DumpDirectoryDriveLetter has less than $($MinimumFreePercentage)% free"
    }
    
    if ($SlackNotifications) {
        Send-SlackNotification @SlackConfig -Message "Drive $DumpDirectoryDriveLetter has less than $($MinimumFreePercentage)% free"
    }
    exit #Exit because we are below the minimum free percentage
}

Write-Verbose "Query the Tablo for a list of IDs to process"
Try {
    $TabloRecordings = (Invoke-RestMethod @RestConfigGet -Uri $TabloRecordingURI).ids
} Catch {
    Write-Verbose 'ERROR! Fallback to use regex to pull the recids'
    $URI = $TabloPVRURI
    $HTMLBody = (Invoke-RestMethod -Uri $URI -Method Get).split('\n')
    $Recs = $HTMLBody -match '<a\s+(?:[^>]*?\s+)?href="([^"]*)"' | Where-Object {($PSItem -notlike "*Pare")}
    $TabloRecordings = $Recs.split('>').split('<') -match '^[0-9]*$' | Where-Object {($PSItem -notlike $null)}
}

Write-Verbose "Setting the location to a working directory"
Set-Location $TempDownload

Write-Verbose "Test SQL connection and exit if it fails"
Test-SQLConnection $ServerInstance

Write-Verbose "Checking for exceptions in SQL, these will be used in the post processing method"
$ShowAirDateExceptionsList = Run-SQLQuery @SQLConfig -Query "SELECT * FROM [dbo].[Air_Date_Exceptions]"  | Select-Object -ExpandProperty AirDateException
$ShowExceptionsList = Run-SQLQuery @SQLConfig -Query "SELECT * FROM [dbo].[Post_Processing_Exceptions]" | Select-Object -ExpandProperty PostProcessException

#Build Foreach Loop to build folders and to download the raw TS files
foreach ($Recording in $TabloRecordings) {

    #Build Metdata from $Recording and Grab JSON Data from Tablo, Will grab the required data as the TV and Movie functions are buried inside of Get-TabloMovieorTV
    Get-TabloRecordingMetaData $Recording

    #SQL Select statement since we will run multiple if statements against it
    $TVSQLSelect = Run-SQLQuery @SQLConfig -Query "SELECT Recid,Processed FROM TV_Recordings where RECID=$Recording"

    #Check if we downloaded the show before
    if (
    (($TVSQLSelect.RecID -eq $null) -or ($TVSQLSelect.Processed -like $null)) -and 
    ((Run-SQLQuery @SQLConfig -Query "SELECT RecID FROM MOVIE_Recordings WHERE RECID=$Recording") -eq $null) -and
    ($RecIsFinished -match "finished|recording") -and
    ($NoMetaData -notmatch $false) -and
    ($Script:EpisodeWarnings -notcontains "http://api.slipstream.nuvyyo.com/warning/recording/tooShort" )) {

            Write-Verbose "Set File name depending on Exceptions List, this needs to go up top to correctly store Air Date Exceptions in SQL"
            if ($ShowAirDateExceptionsList -match $ShowName) {
                $FileName = $FileNameAirDate
            } #Else we will use the the $FileName defined in the metadata function(s)

            #Build Entry to Put into Tablo Database
            $DatabaseEntry = New-Object PSObject -Property @{
                FileName = $FileName -replace "'","''"
                EpisodeName = $EpisodeName -replace "'","''"
                Show = $ShowName -replace "'","''"
                AirDate = $EpisodeOriginalAirDate
                PostProcessDate = (Get-Date)
                Description = $EpisodeDescription -replace "'","''"
                RecID = $Recording
                Media = $MediaType
                EpisodeSeason = $EpisodeSeason
                EpisodeNumber = $EpisodeNumber
            }

            #Check if we are processing a failed download, if not insert everything into SQL
            if (!(($TVSQLSelect.Recid -notlike $null) -and ($TVSQLSelect.Processed -like $null))) {
                Write-Verbose "Build SQL Query to insert the DataBase Entry into the Database"
                if ($MediaType -eq 'TV') {
                #Check if the show exists in the Shows table if not add it to [TV_Shows]
                if (!(Run-SQLQuery @SQLConfig -Query "SELECT SHOW FROM [dbo].[TV_Shows] WHERE SHOW = '$($DatabaseEntry.show)'").Show -eq $DatabaseEntry.Show) {
                    #Update SQL with New Show
                    Run-SQLQuery @SQLConfig -Query "INSERT INTO [dbo].[TV_Shows] (Show) VALUES ('$($DatabaseEntry.Show)')"

                    Write-Verbose "Adding New Show to SickRage if SickRage Support is enabled"
                    if ($EnableSickRageSupport) {
                        Add-ToSickRage -ShowName $DatabaseEntry.Show -SickRageAPIKey $SickRageAPIKey -SickRageURL $SickRageURL
                    }
                }

                    Write-Verbose "Build SQL Insert to insert the entry into SQL [TV_Recordings]"
                    $SQLInsert = "INSERT INTO [dbo].[TV_Recordings] (RecID,FileName,EpisodeName,Show,EpisodeNumber,EpisodeSeason,AirDate,PostProcessDate,Description,Media) VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}','{7}','{8}','{9}')" -f $DatabaseEntry.RecID,$DatabaseEntry.FileName,$DatabaseEntry.EpisodeName,$DatabaseEntry.Show,$DatabaseEntry.EpisodeNumber,$DatabaseEntry.EpisodeSeason,$DatabaseEntry.AirDate,$DatabaseEntry.PostProcessDate,$DatabaseEntry.Description,$DatabaseEntry.Media
                } elseif ($MediaType -eq 'MOVIE') {
                    $SQLInsert = "INSERT INTO [dbo].[MOVIE_Recordings] (RecID,FileName,AirDate,PostProcessDate,Media,Processed) VALUES ('{0}','{1}','{2}','{3}','{4}','')" -f $DatabaseEntry.RecID,$DatabaseEntry.FileName,$DatabaseEntry.AirDate,$DatabaseEntry.PostProcessDate,$DatabaseEntry.Media
                }
                Run-SQLQuery @SQLConfig -Query $SQLInsert
            } else {
                #Remove the folder and start over, we want good files and not bad files
                Remove-Item $Recording -Recurse -Force
            }

            Write-Verbose "Build Variables to Download TS recorded files"
            $RecordingURI = ($TabloPVRURI + $Recording + "/segs/")
            $RecordedLinks = ((Invoke-WebRequest -Uri $RecordingURI).links | Where-Object {($_.href -match '[0-9]')}).href

            Write-Verbose "Create a temporary folder to store the recording files"
            if (!(Test-Path $Recording)) {New-Item ($Recording) -ItemType dir}

            #CD to Download Directory
            Set-Location $Recording

            if ($RecIsFinished -eq 'recording') {
                Write-Verbose "Recording in progress, do until loop to download all the clips from the Tablo, so we can join them together later"
                do {
                    $RecordedLinks = ((Invoke-WebRequest -Uri $RecordingURI).links | Where-Object {($_.href -match '[0-9]')}).href
                    foreach ($Link in $RecordedLinks) {
                        if (!(Test-Path -Path $Link)) {Invoke-WebRequest -URI ($RecordingURI + $Link) -OutFile $Link}
                    }
                    Get-TabloRecordingStatus -Recording $Recording
                    [System.GC]::Collect() #.Net method to clean up the ram
                    Start-Sleep -Seconds 5 #Sleep for a little to prevent slamming the tablo
                } until ($RecIsFinished -eq 'finished')
            } elseif ($RecIsFinished -eq 'finished') {
                Write-Verbose "Recording is finished, downloading all the clips from the Tablo, so we can join them together later"
                foreach ($Link in $RecordedLinks) {
                    Invoke-WebRequest -URI ($RecordingURI + $Link) -OutFile $Link
                }
            }

            #Create String for FFMPEG
            $JoinedTSFiles = ((Get-ChildItem).Name) -join '|'

            Write-Verbose "Run FFMpeg for TV Shows or Movies"
            if ($MediaType -eq 'TV') {
                #Check if the file we are going to create already exists and if so append a timestamp
                Check-ForDuplicateFile $DumpDirectoryTV $FileName

                #Join .TS Clips into a Master Media File for saving
                if ($ShowExceptionsList -match $ShowName) {(& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryExceptions\$FileName.mp4)}
                else {
                    (& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryTV\$FileName.mp4)
                }
            } elseif ($MediaType -eq 'MOVIE') {
                #Check if the file we are going to create already exists and if so append a timestamp
                Check-ForDuplicateFile $DumpDirectoryMovies $FileName

                #Join .TS Clips into a Master Media File for saving
                (& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryMovies\$FileName.mp4)
            }

            Write-Verbose "CD to Root Directory, and remove Temp Files"
            Set-Location $TempDownload
            Remove-Item $Recording -Recurse

            Write-Verbose "Update SQL with recording as processed"
            if ($MediaType -eq 'TV') {
                $SQLInsert = "UPDATE [dbo].[TV_Recordings] SET Processed=1 WHERE Recid=$Recording"
            } elseif ($MediaType -eq 'MOVIE') {
                $SQLInsert = "UPDATE [dbo].[MOVIE_Recordings] SET Processed=1 WHERE Recid=$Recording"
            }

            Run-SQLQuery @SQLConfig -Query $SQLInsert
            #End processing if we matched the metadata
        } else {
            if ($NoMetaData -eq $false) {
                Write-Output "$Recording does not have any metadata, skipping"
        } else {
            Write-Output "$Recording has already been downloaded"
        }
    }

    #Clear Varibles that can cause issues, outside of the if statement so the variables are removed every time
    Remove-Variable RecIsFinished -ErrorAction SilentlyContinue
    Remove-Variable DatabaseEntry -ErrorAction SilentlyContinue
    Remove-Variable NoMetaData -ErrorAction SilentlyContinue
    Remove-Variable ShowException -ErrorAction SilentlyContinue
    Remove-Variable MediaType -ErrorAction SilentlyContinue
    Remove-Variable FileName -ErrorAction SilentlyContinue
    Remove-Variable FileNameAirDate -ErrorAction SilentlyContinue
    Remove-Variable MovieYear -ErrorAction SilentlyContinue
    Remove-Variable ReleaseYear -ErrorAction SilentlyContinue
    Remove-Variable EpisodeDescription -ErrorAction SilentlyContinue
    Remove-Variable SQLInsert -ErrorAction SilentlyContinue
    Remove-Variable ShowName -ErrorAction SilentlyContinue
    Remove-Variable EpisodeSeason -ErrorAction SilentlyContinue
    Remove-Variable EpisodeNumber -ErrorAction SilentlyContinue

    [System.GC]::Collect() #.Net method to clean up the ram
}