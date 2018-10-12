properties {
    $projectRoot = $ENV:BHProjectPath
    if(-not $projectRoot) {
        $projectRoot = $PSScriptRoot
    }

    $sut = $env:BHModulePath
    $tests = "$projectRoot/tests"
    $outputDir = Join-Path -Path $projectRoot -ChildPath 'out'
    $outputModDir = Join-Path -Path $outputDir -ChildPath $env:BHProjectName
    $manifest = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $outputModVerDir = Join-Path -Path $outputModDir -ChildPath $manifest.ModuleVersion
    $psVersion = $PSVersionTable.PSVersion.Major
    $pathSeperator = [IO.Path]::PathSeparator
}

task default -depends Test

task Init {
    "`nSTATUS: Testing with PowerShell $psVersion"
    "Build System Details:"
    Get-Item ENV:BH*
    "`n"

    'Pester', 'PlatyPS', 'PSScriptAnalyzer' | Foreach-Object {
        if (-not (Get-Module -Name $_ -ListAvailable -Verbose:$false -ErrorAction SilentlyContinue)) {
            Install-Module -Name $_ -Repository PSGallery -Scope CurrentUser -AllowClobber -Confirm:$false -ErrorAction Stop
        }
        Import-Module -Name $_ -Verbose:$false -Force -ErrorAction Stop
    }
} -description 'Initialize build environment'

task Test -Depends Init, Analyze, Pester -description 'Run test suite'

task Analyze -Depends Build {
    $analysis = Invoke-ScriptAnalyzer -Path $outputModVerDir -Verbose:$false
    $errors = $analysis | Where-Object {$_.Severity -eq 'Error'}
    $warnings = $analysis | Where-Object {$_.Severity -eq 'Warning'}

    if (($errors.Count -eq 0) -and ($warnings.Count -eq 0)) {
        '    PSScriptAnalyzer passed without errors or warnings'
    }

    if (@($errors).Count -gt 0) {
        Write-Error -Message 'One or more Script Analyzer errors were found. Build cannot continue!'
        $errors | Format-Table
    }

    if (@($warnings).Count -gt 0) {
        Write-Warning -Message 'One or more Script Analyzer warnings were found. These should be corrected.'
        $warnings | Format-Table
    }
} -description 'Run PSScriptAnalyzer'

task Pester -Depends Build {
    Push-Location
    Set-Location -PassThru $outputModDir
    if(-not $ENV:BHProjectPath) {
        Set-BuildEnvironment -Path $PSScriptRoot\..
    }

    $origModulePath = $env:PSModulePath
    if ( $env:PSModulePath.split($pathSeperator) -notcontains $outputDir ) {
        $env:PSModulePath = ($outputDir + $pathSeperator + $origModulePath)
    }

    Remove-Module $ENV:BHProjectName -ErrorAction SilentlyContinue -Verbose:$false
    Import-Module -Name $outputModDir -Force -Verbose:$false
    $testResultsXml = Join-Path -Path $outputDir -ChildPath 'testResults.xml'
    $testResults = Invoke-Pester -Path $tests -PassThru -OutputFile $testResultsXml -OutputFormat NUnitXml

    # Upload test artifacts to AppVeyor
    if ($env:APPVEYOR_JOB_ID) {
        $wc = New-Object 'System.Net.WebClient'
        $wc.UploadFile("https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", $testResultsXml)
    }

    if ($testResults.FailedCount -gt 0) {
        $testResults | Format-List
        Write-Error -Message 'One or more Pester tests failed. Build cannot continue!'
    }
    Pop-Location
    $env:PSModulePath = $origModulePath
} -description 'Run Pester tests'

task CreateMarkdownHelp -Depends Compile {
    # PoshBot functions
    Import-Module -Name $outputModDir -Verbose:$false -Global
    $mdHelpPath = Join-Path -Path $projectRoot -ChildPath 'docs/reference/functions'
    $mdFiles = New-MarkdownHelp -Module $env:BHProjectName -OutputFolder $mdHelpPath -WithModulePage -Force
    "    PoshBot markdown help created at [$mdHelpPath]"

    # Builtin commands
    Import-Module -Name $outputModVerDir/Plugins/Builtin -Verbose:$false -Global
    $mdHelpPath = Join-Path -Path $projectRoot -ChildPath 'docs/reference/commands'
    $mdFiles = New-MarkdownHelp -Module 'Builtin' -OutputFolder $mdHelpPath -WithModulePage -Force
    "    Builtin plugin markdown help created at [$mdHelpPath]"

    @('Builtin', $env:BHProjectName).ForEach({
        Remove-Module -Name $_ -Verbose:$false
    })
} -description 'Create initial markdown help files'

task UpdateMarkdownHelp -Depends Compile {
    #Import-Module -Name $sut -Force -Verbose:$false
    Import-Module -Name $outputModDir -Verbose:$false
    $mdHelpPath = Join-Path -Path $projectRoot -ChildPath 'docs/reference/functions'
    $mdFiles = Update-MarkdownHelpModule -Path $mdHelpPath -Verbose:$false
    "    Markdown help updated at [$mdHelpPath]"
} -description 'Update markdown help files'

task CreateExternalHelp -Depends CreateMarkdownHelp {
    New-ExternalHelp "$projectRoot\docs\reference\functions" -OutputPath "$outputModVerDir\en-US" -Force
} -description 'Create module help from markdown files'

Task RegenerateHelp -Depends UpdateMarkdownHelp, CreateExternalHelp

Task Publish -Depends Test {
    "    Publishing version [$($manifest.ModuleVersion)] to PSGallery..."
    Publish-Module -Path $outputModVerDir -NuGetApiKey $env:PSGalleryApiKey -Repository PSGallery
}

task Clean -depends Init {
    Remove-Module -Name $env:BHProjectName -Force -ErrorAction SilentlyContinue

    if (Test-Path -Path $outputDir) {
        Get-ChildItem -Path $outputDir -Recurse | Remove-Item -Force -Recurse
    } else {
        New-Item -Path $outputDir -ItemType Directory > $null
    }
    "    Cleaned previous output directory [$outputDir]"
} -description 'Cleans module output directory'

task Compile -depends Clean {
    # Create module output directory
    $modDir = New-Item -Path $outputModDir -ItemType Directory
    New-Item -Path $outputModVerDir -ItemType Directory > $null

    # Append items to psm1
    Write-Verbose -Message 'Creating psm1...'
    $psm1 = Copy-Item -Path (Join-Path -Path $sut -ChildPath 'PoshBot.psm1') -Destination (Join-Path -Path $outputModVerDir -ChildPath "$($ENV:BHProjectName).psm1") -PassThru

    # This is dumb but oh well :)
    # We need to write out the classes in a particular order
    $classDir = (Join-Path -Path $sut -ChildPath 'Classes')
    @(
        'Enums'
        'LogMessage'
        'Logger'
        'BaseLogger'
        'ExceptionFormatter'
        'Event'
        'Person'
        'Room'
        'Response'
        'Message'
        'Stream'
        'CommandResult'
        'ParsedCommand'
        'CommandParser'
        'Permission'
        'CommandAuthorizationResult'
        'AccessFilter'
        'Role'
        'Group'
        'Trigger'
        'StorageProvider'
        'RoleManager'
        'Command'
        'CommandHistory'
        'Plugin'
        'PluginCommand'
        'Approver'
        'CommandExecutionContext'
        'CommandExecutor'
        'ScheduledMessage'
        'Scheduler'
        'ConfigProvidedParameter'
        'PluginManager'
        'ConnectionConfig'
        'Connection'
        'Backend'
        'ApprovalCommandConfiguration'
        'ApprovalConfiguration'
        'ChannelRule'
        'BotConfiguration'
        'Bot'
    ) | ForEach-Object {
        Get-Content -Path (Join-Path -Path $classDir -ChildPath "$($_).ps1") | Add-Content -Path $psm1 -Encoding UTF8
    }
    Get-ChildItem -Path (Join-Path -Path $sut -ChildPath 'Private') -Recurse |
        Get-Content -Raw | Add-Content -Path $psm1 -Encoding UTF8
    Get-ChildItem -Path (Join-Path -Path $sut -ChildPath 'Public') -Recurse |
        Get-Content -Raw | Add-Content -Path $psm1 -Encoding UTF8
    Get-ChildItem -Path (Join-Path -Path $sut -ChildPath 'Implementations') -File -Recurse |
        Get-Content -Raw | Add-Content -Path $psm1 -Encoding UTF8

    # Copy over other items
    Copy-Item -Path $env:BHPSModuleManifest -Destination $outputModVerDir
    Copy-Item -Path (Join-Path -Path $classDir -ChildPath 'PoshBotAttribute.ps1') -Destination $outputModVerDir
    Copy-Item -Path (Join-Path -Path $sut -ChildPath 'Plugins') -Destination $outputModVerDir -Recurse
    Copy-Item -Path (Join-Path -Path $sut -ChildPath 'Task') -Destination $outputModVerDir -Recurse

    "    Created compiled module at [$modDir]"
} -description 'Compiles module from source'

task Build -depends Compile, CreateMarkdownHelp {
    # External help
    $helpXml = New-ExternalHelp "$projectRoot\docs\reference\functions" -OutputPath (Join-Path -Path $outputModVerDir -ChildPath 'en-US') -Force
    "    Module XML help created at [$helpXml]"
}

task Build-Docker -depends Test {
    Push-Location
    Set-Location -Path $projectRoot
    $version = $manifest.ModuleVersion.ToString()
    exec {
        & docker build -t poshbotio/poshbot-nano-slack:latest -t poshbotio/poshbot-nano-slack:$version --label version=$version .
    }
    Pop-Location
} -description 'Create Docker container'

task Publish-Docker -depends Build-Docker {
    "    Publishing Docker image [$($manifest.ModuleVersion)] to Docker Hub..."
    $version = $manifest.ModuleVersion.ToString()
    exec {
        docker login
    }
    exec {
        docker push poshbotio/poshbot-nano-slack:latest
        docker push poshbotio/poshbot-nano-slack:$version
    }
}
