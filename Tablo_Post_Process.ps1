#Global Variables
$Tablo = "tablo.domain.tld" #Insert yout IP and DNS Name for the Tablo Here
$TempDownload = "D:\Tablo" #Temporary Download Location
$TabloDatabase = ($TempDownload + "\TabloDatabase.csv")
$TabloRecordingURI = ("http://"+$Tablo+":18080/plex/rec_ids")
$TabloPVRURI = ("http://"+$Tablo+":18080/pvr/")
$FFMPEGBinary = "C:\ffmpeg\bin\ffmpeg.exe" #FFMPEG Location
$DumpDirectory = "D:\Tablo\Processed" #Location where to put finished recordigs

#Recordings Paths
$Recordings = (Invoke-WebRequest -Uri $TabloRecordingURI -ErrorAction Stop).content | ConvertFrom-Json | Select-Object -ExpandProperty ids

#Functions
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
}

#Create Temp Folders if it does not exist
if (!(Test-Path -Path $TempDownload)) {New-Item -Path $TempDownload -ItemType dir -Force}
if (!(Test-Path -Path $DumpDirectory)) {New-Item -Path $DumpDirectory -ItemType dir -Force}

#CD to working directory
Set-Location $TempDownload

#Check if the Database exists if not create irt
if (!(Test-Path -Path $TabloDatabase)) {New-Item $TabloDatabase -ItemType file}

#Build Foreach Loop to build fodlers and to download files
foreach ($Recording in $Recordings) {

    #Build Metdata from $Recording and Grab JSON Data from Tablo
    Get-TabloMetaData $Recording

    #Check if we downloaded the show before
    if (((Import-Csv $TabloDatabase).RecID -notcontains $Recording) -and ($RecIsFinished -eq 'finished') -and ($NoMetaData -notmatch $false)) {

        #Build Entry to Put into Tablo Database
        $DatabaseEntry = @{} | select FileName,EpisodeName,Show,AirDate,PostProcessDate,Description,RecID
        $DatabaseEntry.FileName = $FileName
        $DatabaseEntry.EpisodeName = $EpisodeName
        $DatabaseEntry.Show = $ShowName
        $DatabaseEntry.AirDate = $EpisodeOriginalAirDate
        $DatabaseEntry.PostProcessDate = (Get-Date)
        $DatabaseEntry.Description = $EpisodeDescription
        $DatabaseEntry.RecID = $Recording

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

        #Join .TS Clips into a Master File
        (& $FFMPEGBinary -i "concat:$JoinedTSFiles" -bsf:a aac_adtstoasc -c copy $DumpDirectory\$FileName.mp4)

        #CD to Root Directory, and remove Temp Files
        Set-Location $TempDownload
        Remove-Item $Recording -Recurse

        } else {if (!($NoMetaData)) {Write-Output "$Recording does not have any metadata, skipping"} else {Write-Output "$Recording has already been downloaded"}}

    #Clear Varibles that can cause issues
    Remove-Variable RecIsFinished -ErrorAction SilentlyContinue
    Remove-Variable DatabaseEntry -ErrorAction SilentlyContinue
    Remove-Variable NoMetaData -ErrorAction SilentlyContinue
    }
