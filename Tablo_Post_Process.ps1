#Global Variables
$Tablo = "tablo.domain.tld"
$TempDownload = "D:\Tablo"
$TabloDatabase = ($TempDownload + "\TabloDatabase.csv")
$TabloRecordingURI = ("http://"+$Tablo+":18080/plex/rec_ids")
$TabloPVRURI = ("http://"+$Tablo+":18080/pvr/")
$FFMPEGBinary = "C:\ffmpeg\bin\ffmpeg.exe"
$DumpDirectoryTV = "D:\Tablo\Processed_TV"
$DumpDirectoryMovies = "D:\Tablo\Processed_Movies"

#Exceptions Variables
$DumpDirectoryExceptions = "\\server\media\ByPass_MCEBuddy_Post_Processing" #File path for $ShowExceptionsList
$ShowExceptionsList = Get-Content ($TempDownload + "\Show_Post_Processing_Exceptions.txt") #Used to export recordings directly to a path if you want to avoid a post processing process
$ShowAirDateExceptionsList = Get-Content ($TempDownload + "\Show_Air_Date_Exceptions.txt") #Used to change the file name from what metadata we can pull from the Tablo to the original air date

#Verify exception files exist
if (!(Test-Path -Path $ShowExceptionsList -ErrorAction SilentlyContinue)) {New-Item -Path $ShowExceptionsList -ItemType Dir}
if (!(Test-Path -Path $ShowAirDateExceptionsList -ErrorAction SilentlyContinue)) {New-Item -Path $ShowAirDateExceptionsList -ItemType Dir}

#Recordings Paths
$Recordings = (Invoke-WebRequest -Uri $TabloRecordingURI -ErrorAction Stop).content | ConvertFrom-Json | Select-Object -ExpandProperty ids

#Functions
#Function to Find TV Metadata
Function Get-TabloMetaData ($Recording) {
    #Build URL to Download Metadata JSON
    $MetadataURI = $TabloPVRURI + $Recording + "/meta.txt"
    $JSONMetaData = (Invoke-WebRequest -Uri $MetadataURI -ErrorAction SilentlyContinue).content | ConvertFrom-Json

    #Check if Metadata is Present
    if ($? -eq $false) {$false | Set-Variable NoMetaData -Scope Script}

    #Build HashTable and Episode Data for later Processes
    $JSONMetaData.recSeries.jsonForClient.title | Set-Variable ShowName -Scope Script #Get Show Title
    $JSONMetaData.recepisode.jsonForClient.description | Set-Variable EpisodeDescription -Scope Script #Get Episode Description
    $JSONMetaData.recepisode.jsonForClient.originalAirDate | Set-Variable EpisodeOriginalAirDate -Scope Script #Get Air Date
    $JSONMetaData.recepisode.jsonForClient.title | Set-Variable EpisodeName -Scope Script #Get Episode Title

    #Check for Finished Recordings
    $JSONMetaData.recepisode.jsonForClient.video.state | Set-Variable RecIsFinished -Scope Script #Check if Recording is finished

    #Special Magic as some Characters Piss off FFMPEG, Create File Name
    $JSONEpisode = ($JSONMetaData.recepisode | Select-Object -ExpandProperty jsonForClient)
    $FileName = $ShowName + "-S" +$JSONEpisode.seasonNumber + "E" + $JSONEpisode.episodeNumber
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
        Get-TabloMetaData $Recording
        'TV' | Set-Variable MediaType -Scope Script
    }
}

#Create Temp Folders if it does not exist
if (!(Test-Path -Path $TempDownload)) {New-Item -Path $TempDownload -ItemType dir -Force}
if (!(Test-Path -Path $DumpDirectoryTV)) {New-Item -Path $DumpDirectoryTV -ItemType dir -Force}

#CD to working directory
Set-Location $TempDownload

#Check if the Database exists if not create irt
if (!(Test-Path -Path $TabloDatabase)) {New-Item $TabloDatabase -ItemType file}

#Build Foreach Loop to build folders and to download the raw TS files
foreach ($Recording in $Recordings) {

    #Build Metdata from $Recording and Grab JSON Data from Tablo, Will grag the required data as the TV and Movie functions are buried inside of Get-TabloMovieorTV
    Get-TabloMovieorTV $Recording

    #Check if we downloaded the show before
    if (((Import-Csv $TabloDatabase).RecID -notcontains $Recording) -and ($RecIsFinished -eq 'finished') -and ($NoMetaData -notmatch $false)) {

        #Build Entry to Put into Tablo Database
        $DatabaseEntry = @{} | select FileName,EpisodeName,Show,AirDate,PostProcessDate,Description,RecID,Media
        $DatabaseEntry.FileName = $FileName
        $DatabaseEntry.EpisodeName = $EpisodeName
        $DatabaseEntry.Show = $ShowName
        $DatabaseEntry.AirDate = $EpisodeOriginalAirDate
        $DatabaseEntry.PostProcessDate = (Get-Date)
        $DatabaseEntry.Description = $EpisodeDescription
        $DatabaseEntry.RecID = $Recording
        $DatabaseEntry.Media = $MediaType

        #Add Recording to Database
        $DatabaseEntry | Export-Csv $TabloDatabase -Append -NoTypeInformation

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
            #Join .TS Clips into a Master Media File for saving
            if ($ShowExceptionsList -match $ShowName) {(& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryExceptions\$FileName.mp4)}
            elseif ($ShowAirDateExceptionsList -match $ShowName) {(& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryTV\$FileNameAirDate.mp4)}
            else {(& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryTV\$FileName.mp4)}
        }

        #FFMPEG for Movies
        if ($MediaType -eq 'MOVIE') {
            #Join .TS Clips into a Master Media File for saving
            (& $FFMPEGBinary -y -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectoryMovies\$FileName.mp4)
        }

        #CD to Root Directory, and remove Temp Files
        Set-Location $TempDownload
        Remove-Item $Recording -Recurse

        } else {if ($NoMetaData -eq $false) {Write-Output "$Recording does not have any metadata, skipping"} else {Write-Output "$Recording has already been downloaded"}}

    #Clear Varibles that can cause issues
    Remove-Variable RecIsFinished -ErrorAction SilentlyContinue
    Remove-Variable DatabaseEntry -ErrorAction SilentlyContinue
    Remove-Variable NoMetaData -ErrorAction SilentlyContinue
    Remove-Variable ShowException -ErrorAction SilentlyContinue
    Remove-Variable MediaType -ErrorAction SilentlyContinue
    }
