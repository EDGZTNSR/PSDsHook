using module PSDsHook

#If the module is not in one of the folders listed in ($env:PSModulePath -split "$([IO.Path]::PathSeparator)")
#You must specify the full path to the psm1 file in the above using statement
#Example: using module 'C:\users\thegn\repos\PsDsHook\out\PSDsHook\0.0.1\PSDsHook.psm1'

#Create array of hook properties
[System.Collections.ArrayList]$embedArray = @()

# (optional) specify a thumbnail url to use in the hook
$thumbUrl = 'https://static1.squarespace.com/static/5644323de4b07810c0b6db7b/t/5aa44874e4966bde3633b69c/1520715914043/webhook_resized.png'

#Create embed builder object via the [DiscordEmbed] class
$embedBuilder = [DiscordEmbed]::New(
                    'title',
                    'description'
                )

#Create the field and then add it to the embed. The last value ($true) is if you want it to be in-line or not
$embedBuilder.AddField(
    [DiscordField]::New(
        'field name', 
        'field value/contents', 
        $true
    )
)

$embedBuilder.AddField(
    [DiscordField]::New(
        'field name2',
        'field value2/contents2', 
        $true
    )
)

#Add our thumbnail to the embed
$embedBuilder.AddThumbnail(
    [DiscordThumbnail]::New(
        $thumbUrl
    )
)

#Add purple color
$embedBuilder.WithColor(
    [DiscordColor]::New(
            'purple'
    )
)

#Add the embed to the array created above
$embedArray.Add($embedBuilder) | Out-Null

#Finally, call the function that will send the embed array to the webhook url via the default configuraiton file
Invoke-PSDsHook -EmbedObject $embedArray -Verbose

#Example of using another configuration file:
# Invoke-PSDsHook -EmbedObject $embedArray -ConfigName 'config2' -Verbose