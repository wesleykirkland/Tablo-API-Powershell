#Global Variables
$Tablo = "tablo.lan.local"
$TempDownload = "D:\Tablo"
$TabloDatabase = ($TempDownload + "\TabloDatabase.csv")
$TabloRecordingURI = ("http://"+$Tablo+":18080/plex/rec_ids")
$TabloPVRURI = ("http://"+$Tablo+":18080/pvr/")
$FFMPEGBinary = "C:\ffmpeg\bin\ffmpeg.exe"
$DumpDirectoryTV = "D:\Tablo\Processed_TV"
$DumpDirectoryMovies = "D:\Tablo\Processed_Movies"
#SQL Variables
$ServerInstance = "SQLPDB01"
$Database = "Tablo"

#Exceptions Variables
$DumpDirectoryExceptions = "\\fsp01\torrent\Downloaded Torrents" #File path for $ShowExceptionsList

#Recordings Paths
$Recordings = (Invoke-WebRequest -Uri $TabloRecordingURI -ErrorAction Stop).content | ConvertFrom-Json | Select-Object -ExpandProperty ids

#Functions
#Test SQL Server Connection
Function Test-SQLConnection ($Server) {
    $connectionString = "Data Source=$Server;Integrated Security=true;Initial Catalog=master;Connect Timeout=3;"
    $sqlConn = New-Object ("Data.SqlClient.SqlConnection") $connectionString
    trap
    {
        Write-Error "Cannot connect to $Server.";
        exit
    }

    $sqlConn.Open()
    if ($sqlConn.State -eq 'Open')
    {
        $sqlConn.Close();
    }
}

#Run-SQLQuery
Function Run-SQLQuery {
    #Params
    [CmdletBinding()]
    Param(
    [parameter(position=0)]
        $ServerInstance,
    [parameter(position=1)]
        $Query,
    [parameter(position=2)]
        $Database
    )

    #Open SQL Connection
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection 
    $SqlConnection.ConnectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=True" 
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand 
    $SqlCmd.Connection = $SqlConnection 
    $SqlCmd.CommandText = $Query 
    $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter 
    $SqlAdapter.SelectCommand = $SqlCmd 
    $DataSet = New-Object System.Data.DataSet 
    $a=$SqlAdapter.Fill($DataSet) 
    $SqlConnection.Close() 
    $DataSet.Tables[0]
}

#Function to Find TV Metadata
Function Get-TabloMetaDataTV ($Recording) {
    #Build URL to Download Metadata JSON
    $MetadataURI = $TabloPVRURI + $Recording + "/meta.txt"
    $JSONMetaData = (Invoke-WebRequest -Uri $MetadataURI -ErrorAction SilentlyContinue).content | ConvertFrom-Json

    #Check if Metadata is Present
    if ($? -eq $false) {$false | Set-Variable NoMetaData -Scope Script}

    #Build Variables and Episode Data for later Processes
    $JSONEpisode = ($JSONMetaData.recepisode | Select-Object -ExpandProperty jsonForClient)
    $JSONMetaData.recSeries.jsonForClient.title | Set-Variable ShowName -Scope Script #Get Show Title
    $JSONMetaData.recepisode.jsonForClient.description | Set-Variable EpisodeDescription -Scope Script #Get Episode Description
    $JSONMetaData.recepisode.jsonForClient.originalAirDate | Set-Variable EpisodeOriginalAirDate -Scope Script #Get Air Date
    $JSONMetaData.recepisode.jsonForClient.title | Set-Variable EpisodeName -Scope Script #Get Episode Title
    $JSONEpisode.seasonNumber | Set-Variable EpisodeSeason -Scope Script #Get Episode Season
    $JSONEpisode.episodenumber | Set-Variable EpisodeNumber -Scope Script #Get Episode Number

    #Check for Finished Recordings
    $JSONMetaData.recepisode.jsonForClient.video.state | Set-Variable RecIsFinished -Scope Script #Check if Recording is finished

    #Special Magic as some Characters Piss off FFMPEG, Create File Name
    $FileName = $ShowName + "-S" +$EpisodeSeason + "E" + $EpisodeNumber
    [string]$FileName.Replace(":","") | Set-Variable FileName -Scope Script

    #Special Magic as some Characters Piss off FFMPEG, Create File Name as AirDate
    $JSONEpisode = ($JSONMetaData.recepisode | Select-Object -ExpandProperty jsonForClient)
    $ModifiedAirDate = ($EpisodeOriginalAirDate).Split("-")
    $ModifiedAirDate = $ModifiedAirDate[1] + '.' + $ModifiedAirDate[2] + '.' + $ModifiedAirDate[0]
    $FileName = $ShowName + " " + $ModifiedAirDate
    [string]$FileName.Replace(":","").Replace("-",".") | Set-Variable FileNameAirDate -Scope Script
}

#Function to Find Movie Metadata
Function Get-TabloMetaDataMovie ($Recording) {
    #Build URL to Download Metadata JSON
    $MetadataURI = $TabloPVRURI + $Recording + "/meta.txt"
    $JSONMetaData = (Invoke-WebRequest -Uri $MetadataURI -ErrorAction SilentlyContinue).content | ConvertFrom-Json

    #Check if Metadata is Present
    if ($? -eq $false) {$false | Set-Variable NoMetaData -Scope Script}

    #Build HashTable and Episode Data for later Processes
    $JSONMetaData.recMovieAiring.jsonFromTribune.program.releaseYear | Set-Variable ReleaseYear -Scope Script #Get Release Year
    $JSONMetaData.recMovieAiring.jsonFromTribune.program.title | Set-Variable MovieName -Scope Script #Get Episode Title

    #Check for Finished Recordings
    $JSONMetaData.recMovieAiring.jsonForClient.video.state | Set-Variable RecIsFinished -Scope Script #Check if Recording is finished

    #Special Magic as some Characters Piss off FFMPEG, Create File Name
    $JSONEpisode = ($JSONMetaData.recepisode | Select-Object -ExpandProperty jsonForClient)
    $FileName = $MovieName + " (" +$ReleaseYear + ")"
    [string]$FileName.Replace(":","") | Set-Variable FileName -Scope Script
}

#Function to check if we are processing a Movie or a TV Show
Function Get-TabloMovieorTV ($Recording) {
    #Check if we are processing a movie or a TV Show
    $MetadataURI = $TabloPVRURI + $Recording + "/meta.txt"
    $JSONMetaData = (Invoke-WebRequest -Uri $MetadataURI -ErrorAction SilentlyContinue).content | ConvertFrom-Json

    #Check if Metadata is Present
    if ($? -eq $false) {$false | Set-Variable NoMetaData -Scope Script}

    #What to do if we are processing a Movie
    if ($JSONMetaData.recMovie) {
        Get-TabloMetaDataMovie $Recording
        'MOVIE' | Set-Variable MediaType -Scope Script
    }

    #What to do if we are processing a TV Show
    if ($JSONMetaData.recepisode) {
        Get-TabloMetaDataTV $Recording
        'TV' | Set-Variable MediaType -Scope Script
    }
}

#Function to checkif the file we are going to create already exists and if so append a timestamp
Function Check-ForDuplicateFile ($Directory,$FileName) {
    if (Test-Path -Path $Directory\$FileName -ErrorAction SilentlyContinue) {$FileName + '-' + (Get-Date -Format HH:MM-yyyy-mm-dd) | Set-Variable FileName -Scope Script} #Else do nothing and leave the file name alone.
}

#Function to auto add new shows to SickRage
Function AddToSickRage ($ShowName) {
    $SickRageURL = 'https://torrent:8081' #No Trailing '/'
    $SickRageAPIKey = '24905c2fef38de5a7d91003db024e2f0'
     
    #Find the TVDB ID
    $TVDBResults = Invoke-RestMethod -Method Get -Uri "$SickRageURL/api/$SickRageAPIKey/?cmd=sb.searchtvdb&name=$ShowName"
 
    #Verify we successfully ran the query, and atleast 1 or more data results as well as the result is in english
    If (($TVDBResults.result -eq 'success') -and ($TVDBResults.data.results.name -ge '1') -and ($TVDBResults.data.langid -eq '7')) {
        #Select the correct results based upon the most recent show
        $TVDBObject = $TVDBResults.data.results | Sort-Object first_aired -Descending | Select-Object -First 1
 
        #Add the show to SickRage
        Invoke-WebRequest -Method Get -Uri "$SickRageURL/api/$SickRageAPIKey/?cmd=show.addnew&future_status=skipped&lang=en&tvdbid=$($TVDBObject.tvdbid)"
        
        Send-MailMessage -To 'alerts@wesleyk.me' -From ($env:COMPUTERNAME + "@relay.lan.local") -Subject "New Show '$($TVDBObject.name)' Auto added to SickRage" -SmtpServer relay.lan.local
    }
}

##########################################################################################################################################################################################################################################################################################################################
#Start of the actual script

#Create Temp Folders if it does not exist
if (!(Test-Path -Path $TempDownload)) {New-Item -Path $TempDownload -ItemType dir -Force}
if (!(Test-Path -Path $DumpDirectoryTV)) {New-Item -Path $DumpDirectoryTV -ItemType dir -Force}

#Set Location to working directory
Set-Location $TempDownload

#Test for SQL Server Connection
Test-SQLConnection $ServerInstance

#Check for Exceptions
$ShowAirDateExceptionsList = Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query "select * from [dbo].[Air_Date_Exceptions]"  | Select-Object -ExpandProperty AirDateException
$ShowExceptionsList = Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query "select * from [dbo].[Post_Processing_Exceptions]" | Select-Object -ExpandProperty PostProcessException

#Build Foreach Loop to build folders and to download the raw TS files
foreach ($Recording in $Recordings) {

    #Build Metdata from $Recording and Grab JSON Data from Tablo, Will grab the required data as the TV and Movie functions are buried inside of Get-TabloMovieorTV
    Get-TabloMovieorTV $Recording

    #Check if we downloaded the show before
    if (
    ((Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query "SELECT RecID from TV_Recordings where RECID=$Recording") -eq $null)`
     -and ((Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query "SELECT RecID from MOVIE_Recordings where RECID=$Recording") -eq $null)`
     -and ($RecIsFinished -eq 'finished')`
     -and ($NoMetaData -notmatch $false)) {

        #Set File name depending on Exceptions List, this needs to go up top to correctly store Air Date Exceptions in SQL
        if ($ShowAirDateExceptionsList -match $ShowName) {$FileName = $FileNameAirDate} #Else we will use the the $FileName defined in the metadata function(s)

        #Build Entry to Put into Tablo Database
        $DatabaseEntry = @{} | Select-Object FileName,EpisodeName,Show,AirDate,PostProcessDate,Description,RecID,Media,EpisodeSeason,EpisodeNumber
        $DatabaseEntry.FileName = $FileName -replace "'","''"
        $DatabaseEntry.EpisodeName = $EpisodeName -replace "'","''"
        $DatabaseEntry.Show = $ShowName -replace "'","''"
        $DatabaseEntry.AirDate = $EpisodeOriginalAirDate
        $DatabaseEntry.PostProcessDate = (Get-Date)
        $DatabaseEntry.Description = $EpisodeDescription -replace "'","''"
        $DatabaseEntry.RecID = $Recording
        $DatabaseEntry.Media = $MediaType
        $DatabaseEntry.EpisodeSeason = $EpisodeSeason
        $DatabaseEntry.EpisodeNumber = $EpisodeNumber

        #Build INSERT Query String
        if ($MediaType -eq 'TV') {
            #Check if the show exists in the Shows table if not add it to [TV_Shows]
            if (!(Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query "SELECT SHOW FROM [dbo].[TV_Shows] WHERE SHOW = '$($DatabaseEntry.show)'").Show -eq $DatabaseEntry.Show) {
                #Update SQL with New Show
                Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query "INSERT INTO [dbo].[TV_Shows] (Show) VALUES ('$($DatabaseEntry.Show)')"

                #Add show to SickRage
                AddToSickRage -ShowName $DatabaseEntry.Show
            }

            #Build SQL Insert to insert the entry into SQL [TV_Recordings]
            $SQLInsert = "INSERT INTO [dbo].[TV_Recordings] (RecID,FileName,EpisodeName,Show,EpisodeNumber,EpisodeSeason,AirDate,PostProcessDate,Description,Media) VALUES('{0}','{1}','{2}','{3}','{4}','{5}','{6}','{7}','{8}','{9}')" -f $DatabaseEntry.RecID,$DatabaseEntry.FileName,$DatabaseEntry.EpisodeName,$DatabaseEntry.Show,$DatabaseEntry.EpisodeNumber,$DatabaseEntry.EpisodeSeason,$DatabaseEntry.AirDate,$DatabaseEntry.PostProcessDate,$DatabaseEntry.Description,$DatabaseEntry.Media
        } elseif ($MediaType -eq 'MOVIE') {
            $SQLInsert = "INSERT INTO [dbo].[MOVIE_Recordings] (RecID,FileName,AirDate,PostProcessDate,Media,Processed) VALUES('{0}','{1}','{2}','{3}','{4}','')" -f $DatabaseEntry.RecID,$DatabaseEntry.FileName,$DatabaseEntry.AirDate,$DatabaseEntry.PostProcessDate,$DatabaseEntry.Media
            }


        #Insert into SQL
        Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query $SQLInsert

        #Build Variables to Download TS recorded files
        $RecordingURI = ($TabloPVRURI + $Recording + "/segs/")
        $RecordedLinks = ((Invoke-WebRequest -Uri $RecordingURI).links | select -Skip 1).href

        #Create Temp Folder
        if (!(Test-Path ($Recording))) {New-Item ($Recording) -ItemType dir}

        #CD to Download Directory
        Set-Location $Recording

        foreach ($Link in $RecordedLinks) {#
            Invoke-WebRequest -URI ($RecordingURI + $Link) -OutFile $Link
            }

        #Create String for FFMPEG
        $JoinedTSFiles = ((Get-ChildItem).Name) -join '|'

        #FFMPEG for TV Shows
        if ($MediaType -eq 'TV') {
            #Check if the file we are going to create already exists and if so append a timestamp
            Check-ForDuplicateFile $DumpDirectoryTV $FileName

            #Join .TS Clips into a Master Media File for saving
            if ($ShowExceptionsList -match $ShowName) {(& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryExceptions\$FileName.mp4)}
            else {(& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryTV\$FileName.mp4)}
        }

        #FFMPEG for Movies
        if ($MediaType -eq 'MOVIE') {
            #Check if the file we are going to create already exists and if so append a timestamp
            Check-ForDuplicateFile $DumpDirectoryMovies $FileName

            #Join .TS Clips into a Master Media File for saving
            (& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryMovies\$FileName.mp4)
        }

        #CD to Root Directory, and remove Temp Files
        Set-Location $TempDownload
        Remove-Item $Recording -Recurse

        #Update SQL with recording as processed
        #Build Processed Query String
        if ($MediaType -eq 'TV') {
            $SQLInsert = "Update [dbo].[TV_Recordings] SET Processed=1 where Recid=$Recording"
        } elseif ($MediaType -eq 'MOVIE') {
            $SQLInsert = "Update [dbo].[MOVIE_Recordings] SET Processed=1 where Recid=$Recording"
            }
        Run-SQLQuery -ServerInstance $ServerInstance -Database $Database -Query $SQLInsert

        } else {if ($NoMetaData -eq $false) {Write-Output "$Recording does not have any metadata, skipping"} else {Write-Output "$Recording has already been downloaded"}}

    #Clear Varibles that can cause issues, outside of the If statement so the variables are removed every time
    Remove-Variable RecIsFinished -ErrorAction SilentlyContinue
    Remove-Variable DatabaseEntry -ErrorAction SilentlyContinue
    Remove-Variable NoMetaData -ErrorAction SilentlyContinue
    Remove-Variable ShowException -ErrorAction SilentlyContinue
    Remove-Variable MediaType -ErrorAction SilentlyContinue
    Remove-Variable FileName -ErrorAction SilentlyContinue
    Remove-Variable FileNameAirDate -ErrorAction SilentlyContinue
    Remove-Variable JSONEpisode -ErrorAction SilentlyContinue
    Remove-Variable MovieYear -ErrorAction SilentlyContinue
    Remove-Variable ReleaseYear -ErrorAction SilentlyContinue
    Remove-Variable EpisodeDescription -ErrorAction SilentlyContinue
    Remove-Variable SQLInsert -ErrorAction SilentlyContinue
    Remove-Variable ShowName -ErrorAction SilentlyContinue
    Remove-Variable EpisodeSeason -ErrorAction SilentlyContinue
    Remove-Variable EpisodeNumber -ErrorAction SilentlyContinue
}