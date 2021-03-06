using module PSDsHook

#If the module is not in one of the folders listed in ($env:PSModulePath -split "$([IO.Path]::PathSeparator)")
#You must specify the full path to the psm1 file in the above using statement
#Example: using module 'C:\users\thegn\repos\PsDsHook\out\PSDsHook\0.0.1\PSDsHook.psm1'

#Create array of hook properties
[System.Collections.ArrayList]$embedArray = @()

#Create embed builder object via the [DiscordEmbed] class
$embedBuilder = [DiscordEmbed]::New(
                    'title',
                    'description'
                )

#Add blue color
$embedBuilder.WithColor(
    [DiscordColor]::New(
            'blue'
    )
)

#Add the embed to the array created above
$embedArray.Add($embedBuilder) | Out-Null

#Finally, call the function that will send the embed array to the webhook url via the default configuraiton file
Invoke-PSDsHook -EmbedObject $embedArray -Verbose

#Example of using another configuration file:
# Invoke-PSDsHook -EmbedObject $embedArray -ConfigName 'config2' -Verbose