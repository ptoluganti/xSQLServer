# Load Localization Data
Import-LocalizedData LocalizedData -filename xSQLServer.strings.psd1 -ErrorAction SilentlyContinue
Import-LocalizedData USLocalizedData -filename xSQLServer.strings.psd1 -UICulture en-US -ErrorAction SilentlyContinue

<#
    .SYNOPSIS
        Connect to a SQL Server Database Engine and return the server object.

    .PARAMETER SQLServer
        String containing the host name of the SQL Server to connect to.

    .PARAMETER SQLInstanceName
        String containing the SQL Server Database Engine instance to connect to.

    .PARAMETER SetupCredential
        PSCredential object with the credentials to use to impersonate a user when connecting.
        If this is not provided then the current user will be used to connect to the SQL Server Database Engine instance.
#>
function Connect-SQL
{
    [CmdletBinding()]
    param
    (
        [ValidateNotNull()]
        [System.String]
        $SQLServer = $env:COMPUTERNAME,

        [ValidateNotNull()]
        [System.String]
        $SQLInstanceName = "MSSQLSERVER",

        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        $SetupCredential
    )

    $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo')

    if ($SQLInstanceName -eq "MSSQLSERVER")
    {
        $connectSql = $SQLServer
    }
    else
    {
        $connectSql = "$SQLServer\$SQLInstanceName"
    }

    if ($SetupCredential)
    {
        $sql = New-Object Microsoft.SqlServer.Management.Smo.Server
        $sql.ConnectionContext.ConnectAsUser = $true
        $sql.ConnectionContext.ConnectAsUserPassword = $SetupCredential.GetNetworkCredential().Password
        $sql.ConnectionContext.ConnectAsUserName = $SetupCredential.GetNetworkCredential().UserName
        $sql.ConnectionContext.ServerInstance = $connectSQL
        $sql.ConnectionContext.connect()
    }
    else
    {
        $sql = New-Object Microsoft.SqlServer.Management.Smo.Server $connectSql
    }

    if (!$sql)
    {
        throw "Failed connecting to SQL $connectSql"
    }

    New-VerboseMessage -Message "Connected to SQL $connectSql"

    return $sql
}

<#
    .SYNOPSIS
        Connect to a SQL Server Analysis Service and return the server object.

    .PARAMETER SQLServer
        String containing the host name of the SQL Server to connect to.

    .PARAMETER SQLInstanceName
        String containing the SQL Server Analysis Service instance to connect to.

    .PARAMETER SetupCredential
        PSCredential object with the credentials to use to impersonate a user when connecting.
        If this is not provided then the current user will be used to connect to the SQL Server Analysis Service instance.
#>
function Connect-SQLAnalysis
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLServer = $env:COMPUTERNAME,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLInstanceName = 'MSSQLSERVER',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $SetupCredential
    )

    $null = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.AnalysisServices')

    if ($SQLInstanceName -eq 'MSSQLSERVER')
    {
        $analysisServiceInstance = $SQLServer
    }
    else
    {
        $analysisServiceInstance = "$SQLServer\$SQLInstanceName"
    }

    if ($SetupCredential)
    {
        $userName = $SetupCredential.GetNetworkCredential().UserName
        $password = $SetupCredential.GetNetworkCredential().Password

        $analysisServicesDataSource = "Data Source=$analysisServiceInstance;User ID=$userName;Password=$password"
    }
    else
    {
        $analysisServicesDataSource = "Data Source=$analysisServiceInstance"
    }

    try
    {
        $analysisServicesObject = New-Object -TypeName Microsoft.AnalysisServices.Server
        if ($analysisServicesObject)
        {
            $analysisServicesObject.Connect($analysisServicesDataSource)
        }
        else
        {
            throw New-TerminatingError -ErrorType AnalysisServicesNoServerObject -ErrorCategory InvalidResult
        }

        Write-Verbose -Message "Connected to Analysis Services $analysisServiceInstance." -Verbose
    }
    catch
    {
        throw New-TerminatingError -ErrorType AnalysisServicesFailedToConnect -FormatArgs @($analysisServiceInstance) -ErrorCategory ObjectNotFound -InnerException $_.Exception
    }

    return $analysisServicesObject
}

<#
    .SYNOPSIS
        Creates a new application domain and loads the assemblies Microsoft.SqlServer.Smo
        for the correct SQL Server major version.

        An isolated application domain is used to load version specific assemblies, this needed
        if there is multiple versions of SQL server in the same configuration. So that a newer
        version of SQL is not using an older version of the assembly, or vice verse.

        This should be unloaded using the helper function Unregister-SqlAssemblies or
        using [System.AppDomain]::Unload($applicationDomainObject).

    .PARAMETER SQLInstanceName
        String containing the SQL Server Database Engine instance name to get the major SQL version from.

    .PARAMETER ApplicationDomain
        An optional System.AppDomain object to load the assembly into.

    .OUTPUTS
        System.AppDomain. Returns the application domain object with SQL SMO loaded.
#>
function Register-SqlSmo
{
    [CmdletBinding()]
    [OutputType([System.AppDomain])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLInstanceName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.AppDomain]
        $ApplicationDomain
    )

    $sqlMajorVersion = Get-SqlInstanceMajorVersion -SQLInstanceName $SQLInstanceName
    New-VerboseMessage -Message ('SQL major version is {0}.' -f $sqlMajorVersion)

    if( -not $ApplicationDomain )
    {
        $applicationDomainName = $MyInvocation.MyCommand.ModuleName
        New-VerboseMessage -Message ('Creating application domain ''{0}''.' -f $applicationDomainName)
        $applicationDomainObject = [System.AppDomain]::CreateDomain($applicationDomainName)
    }
    else
    {
        New-VerboseMessage -Message ('Reusing application domain ''{0}''.' -f $ApplicationDomain.FriendlyName)
        $applicationDomainObject = $ApplicationDomain
    }

    $sqlSmoAssemblyName = "Microsoft.SqlServer.Smo, Version=$sqlMajorVersion.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
    New-VerboseMessage -Message ('Loading assembly ''{0}''.' -f $sqlSmoAssemblyName)
    $applicationDomainObject.Load($sqlSmoAssemblyName) | Out-Null

    return $applicationDomainObject
}

<#
    .SYNOPSIS
        Creates a new application domain and loads the assemblies Microsoft.SqlServer.Smo and
        Microsoft.SqlServer.SqlWmiManagement for the correct SQL Server major version.

        An isolated application domain is used to load version specific assemblies, this needed
        if there is multiple versions of SQL server in the same configuration. So that a newer
        version of SQL is not using an older version of the assembly, or vice verse.

        This should be unloaded using the helper function Unregister-SqlAssemblies or
        using [System.AppDomain]::Unload($applicationDomainObject) preferably in a finally block.

    .PARAMETER SQLInstanceName
        String containing the SQL Server Database Engine instance name to get the major SQL version from.

    .PARAMETER ApplicationDomain
        An optional System.AppDomain object to load the assembly into.

    .OUTPUTS
        System.AppDomain. Returns the application domain object with SQL WMI Management loaded.
#>
function Register-SqlWmiManagement
{
    [CmdletBinding()]
    [OutputType([System.AppDomain])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SQLInstanceName,

        [Parameter()]
        [ValidateNotNull()]
        [System.AppDomain]
        $ApplicationDomain
    )

    $sqlMajorVersion = Get-SqlInstanceMajorVersion -SQLInstanceName $SQLInstanceName
    New-VerboseMessage -Message ('SQL major version is {0}.' -f $sqlMajorVersion)

    <#
        Must register Microsoft.SqlServer.Smo first because that is a
        dependency of Microsoft.SqlServer.SqlWmiManagement.
    #>
    if (-not $ApplicationDomain)
    {
        $applicationDomainObject = Register-SqlSmo -SQLInstanceName $SQLInstanceName
    }
    # Returns zero (0) objects if the assembly is not found
    elseif (-not ($ApplicationDomain.GetAssemblies().FullName -match 'Microsoft.SqlServer.Smo'))
    {
        $applicationDomainObject = Register-SqlSmo -SQLInstanceName $SQLInstanceName -ApplicationDomain $ApplicationDomain
    }

    $sqlSqlWmiManagementAssemblyName = "Microsoft.SqlServer.SqlWmiManagement, Version=$sqlMajorVersion.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
    New-VerboseMessage -Message ('Loading assembly ''{0}''.' -f $sqlSqlWmiManagementAssemblyName)
    $applicationDomainObject.Load($sqlSqlWmiManagementAssemblyName) | Out-Null

    return $applicationDomainObject
}

<#
    .SYNOPSIS
        Unloads all assemblies in an application domain. It unloads the application domain.

    .PARAMETER ApplicationDomain
        System.AppDomain object containing the SQL assemblies to unload.
#>
function Unregister-SqlAssemblies
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.AppDomain]
        $ApplicationDomain
    )

    New-VerboseMessage -Message ('Unloading application domain ''{0}''.' -f $ApplicationDomain.FriendlyName)
    [System.AppDomain]::Unload($ApplicationDomain)
}

<#
    .SYNOPSIS
        Returns the major SQL version for the specific instance.

    .PARAMETER SQLInstanceName
        String containing the name of the SQL instance to be configured. Default value is 'MSSQLSERVER'.

    .OUTPUTS
        System.UInt16. Returns the SQL Server major version number.
#>
function Get-SqlInstanceMajorVersion
{
    [CmdletBinding()]
    [OutputType([System.UInt16])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLInstanceName = 'MSSQLSERVER'
    )

    $sqlInstanceId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').$SQLInstanceName
    $sqlVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$sqlInstanceId\Setup").Version

    if (-not $sqlVersion)
    {
        throw New-TerminatingError -ErrorType SqlServerVersionIsInvalid -FormatArgs @($SQLInstanceName) -ErrorCategory InvalidResult
    }

    [System.UInt16] $sqlMajorVersionNumber = $sqlVersion.Split('.')[0]

    return $sqlMajorVersionNumber
}

<#
    .SYNOPSIS
        Returns a localized error message.

    .PARAMETER ErrorType
        String containing the key of the localized error message.

    .PARAMETER FormatArgs
        Collection of strings to replace format objects in the error message.

    .PARAMETER ErrorCategory
        The category to use for the error message. Default value is 'OperationStopped'.
        Valid values are a value from the enumeration System.Management.Automation.ErrorCategory.

    .PARAMETER TargetObject
        The object that was being operated on when the error occurred.

    .PARAMETER InnerException
        Exception object that was thrown when the error occurred, which will be added to the final error message.
#>
function New-TerminatingError
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ErrorType,

        [Parameter(Mandatory = $false)]
        [String[]]
        $FormatArgs,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory = [System.Management.Automation.ErrorCategory]::OperationStopped,

        [Parameter(Mandatory = $false)]
        [Object]
        $TargetObject = $null,

        [Parameter(Mandatory = $false)]
        [System.Exception]
        $InnerException = $null
    )

    $errorMessage = $LocalizedData.$ErrorType

    if(!$errorMessage)
    {
        $errorMessage = ($LocalizedData.NoKeyFound -f $ErrorType)

        if(!$errorMessage)
        {
            $errorMessage = ("No Localization key found for key: {0}" -f $ErrorType)
        }
    }

    $errorMessage = ($errorMessage -f $FormatArgs)

    if( $InnerException )
    {
        $errorMessage += " InnerException: $($InnerException.Message)"
    }

    $callStack = Get-PSCallStack

    # Get Name of calling script
    if($callStack[1] -and $callStack[1].ScriptName)
    {
        $scriptPath = $callStack[1].ScriptName

        $callingScriptName = $scriptPath.Split('\')[-1].Split('.')[0]

        $errorId = "$callingScriptName.$ErrorType"
    }
    else
    {
        $errorId = $ErrorType
    }

    Write-Verbose -Message "$($USLocalizedData.$ErrorType -f $FormatArgs) | ErrorType: $errorId"

    $exception = New-Object System.Exception $errorMessage, $InnerException
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $ErrorCategory, $TargetObject

    return $errorRecord
}

<#
    .SYNOPSIS
        Displays a localized warning message.

    .PARAMETER WarningType
        String containing the key of the localized warning message.

    .PARAMETER FormatArgs
        Collection of strings to replace format objects in warning message.
#>
function New-WarningMessage
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $WarningType,

        [String[]]
        $FormatArgs
    )

    ## Attempt to get the string from the localized data
    $warningMessage = $LocalizedData.$WarningType

    ## Ensure there is a message present in the localization file
    if (!$warningMessage)
    {
        $errorParams = @{
            ErrorType = 'NoKeyFound'
            FormatArgs = $WarningType
            ErrorCategory = 'InvalidArgument'
            TargetObject = 'New-WarningMessage'
        }

        ## Raise an error indicating the localization data is not present
        throw New-TerminatingError @errorParams
    }

    ## Apply formatting
    $warningMessage = $warningMessage -f $FormatArgs

    ## Write the message as a warning
    Write-Warning -Message $warningMessage
}

<#
    .SYNOPSIS
    Displays a standardized verbose message.

    .PARAMETER Message
    String containing the key of the localized warning message.
#>
function New-VerboseMessage
{
    [CmdletBinding()]
    [Alias()]
    [OutputType([String])]
    Param
    (
        [Parameter(Mandatory=$true)]
        $Message
    )
    Write-Verbose -Message ((Get-Date -format yyyy-MM-dd_HH-mm-ss) + ": $Message") -Verbose
}

<#
    .SYNOPSIS
        This method is used to compare current and desired values for any DSC resource.

    .PARAMETER CurrentValues
        This is hash table of the current values that are applied to the resource.

    .PARAMETER DesiredValues
        This is a PSBoundParametersDictionary of the desired values for the resource.

    .PARAMETER ValuesToCheck
        This is a list of which properties in the desired values list should be checked.
        If this is empty then all values in DesiredValues are checked.
#>
function Test-SQLDscParameterState
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [HashTable]
        $CurrentValues,

        [Parameter(Mandatory = $true)]
        [Object]
        $DesiredValues,

        [Parameter()]
        [Array]
        $ValuesToCheck
    )

    $returnValue = $true

    if (($DesiredValues.GetType().Name -ne "HashTable") `
        -and ($DesiredValues.GetType().Name -ne "CimInstance") `
        -and ($DesiredValues.GetType().Name -ne "PSBoundParametersDictionary"))
    {
        throw "Property 'DesiredValues' in Test-SQLDscParameterState must be either a " + `
              "Hash table, CimInstance or PSBoundParametersDictionary. Type detected was $($DesiredValues.GetType().Name)"
    }

    if (($DesiredValues.GetType().Name -eq "CimInstance") -and ($null -eq $ValuesToCheck))
    {
        throw "If 'DesiredValues' is a CimInstance then property 'ValuesToCheck' must contain a value"
    }

    if (($null -eq $ValuesToCheck) -or ($ValuesToCheck.Count -lt 1))
    {
        $keyList = $DesiredValues.Keys
    }
    else
    {
        $keyList = $ValuesToCheck
    }

    $keyList | ForEach-Object -Process {
        if (($_ -ne "Verbose"))
        {
            if (($CurrentValues.ContainsKey($_) -eq $false) `
            -or ($CurrentValues.$_ -ne $DesiredValues.$_) `
            -or (($DesiredValues.GetType().Name -ne 'CimInstance' -and $DesiredValues.ContainsKey($_) -eq $true) -and ($null -ne $DesiredValues.$_ -and $DesiredValues.$_.GetType().IsArray)))
            {
                if ($DesiredValues.GetType().Name -eq "HashTable" -or `
                    $DesiredValues.GetType().Name -eq "PSBoundParametersDictionary")
                {
                    $checkDesiredValue = $DesiredValues.ContainsKey($_)
                }
                else
                {
                    # If DesiredValue is a CimInstance.
                    $checkDesiredValue = $false
                    if (([System.Boolean]($DesiredValues.PSObject.Properties.Name -contains $_)) -eq $true)
                    {
                        if ($null -ne $DesiredValues.$_)
                        {
                            $checkDesiredValue = $true
                        }
                    }
                }

                if ($checkDesiredValue)
                {
                    $desiredType = $DesiredValues.$_.GetType()
                    $fieldName = $_
                    if ($desiredType.IsArray -eq $true)
                    {
                        if (($CurrentValues.ContainsKey($fieldName) -eq $false) `
                        -or ($null -eq $CurrentValues.$fieldName))
                        {
                            New-VerboseMessage -Message ("Expected to find an array value for " + `
                                                         "property $fieldName in the current " + `
                                                         "values, but it was either not present or " + `
                                                         "was null. This has caused the test method " + `
                                                         "to return false.")

                            $returnValue = $false
                        }
                        else
                        {
                            $arrayCompare = Compare-Object -ReferenceObject $CurrentValues.$fieldName `
                                                           -DifferenceObject $DesiredValues.$fieldName
                            if ($null -ne $arrayCompare)
                            {
                                New-VerboseMessage -Message ("Found an array for property $fieldName " + `
                                                             "in the current values, but this array " + `
                                                             "does not match the desired state. " + `
                                                             "Details of the changes are below.")
                                $arrayCompare | ForEach-Object -Process {
                                    New-VerboseMessage -Message "$($_.InputObject) - $($_.SideIndicator)"
                                }

                                $returnValue = $false
                            }
                        }
                    }
                    else
                    {
                        switch ($desiredType.Name)
                        {
                            "String" {
                                if (-not [String]::IsNullOrEmpty($CurrentValues.$fieldName) -or `
                                    -not [String]::IsNullOrEmpty($DesiredValues.$fieldName))
                                {
                                    New-VerboseMessage -Message ("String value for property $fieldName does not match. " + `
                                                                 "Current state is '$($CurrentValues.$fieldName)' " + `
                                                                 "and desired state is '$($DesiredValues.$fieldName)'")

                                    $returnValue = $false
                                }
                            }
                            "Int32" {
                                if (-not ($DesiredValues.$fieldName -eq 0) -or `
                                    -not ($null -eq $CurrentValues.$fieldName))
                                {
                                    New-VerboseMessage -Message ("Int32 value for property " + "$fieldName does not match. " + `
                                                                 "Current state is " + "'$($CurrentValues.$fieldName)' " + `
                                                                 "and desired state is " + "'$($DesiredValues.$fieldName)'")

                                    $returnValue = $false
                                }
                            }
                            "Int16" {
                                if (-not ($DesiredValues.$fieldName -eq 0) -or `
                                    -not ($null -eq $CurrentValues.$fieldName))
                                {
                                    New-VerboseMessage -Message ("Int32 value for property " + "$fieldName does not match. " + `
                                                                 "Current state is " + "'$($CurrentValues.$fieldName)' " + `
                                                                 "and desired state is " + "'$($DesiredValues.$fieldName)'")

                                    $returnValue = $false
                                }
                            }
                            default {
                                Write-Warning -Message ("Unable to compare property $fieldName " + `
                                                             "as the type ($($desiredType.Name)) is " + `
                                                             "not handled by the Test-SQLDscParameterState cmdlet")

                                $returnValue = $false
                            }
                        }
                    }
                }
            }
        }
    }

    return $returnValue
}

<#
    .SYNOPSIS
        Imports the module SQLPS in a standardized way.
#>
function Import-SQLPSModule
{
    [CmdletBinding()]
    param()

    $module = (Get-Module -FullyQualifiedName 'SqlServer' -ListAvailable).Name
    if ($module)
    {
        New-VerboseMessage -Message 'Preferred module SqlServer found.'
    }
    else
    {
        New-VerboseMessage -Message 'Module SqlServer not found, trying to use older SQLPS module.'
        $module = (Get-Module -FullyQualifiedName 'SQLPS' -ListAvailable).Name
    }

    if ($module)
    {
        try
        {
            Write-Debug -Message 'SQLPS module changes CWD to SQLSERVER:\ when loading, pushing location to pop it when module is loaded.'
            Push-Location

            New-VerboseMessage -Message ('Importing {0} module.' -f $module)

            <#
                SQLPS has unapproved verbs, disable checking to ignore Warnings.
                Suppressing verbose so all cmdlet is not listed.
            #>
            Import-Module -Name $module -DisableNameChecking -Verbose:$False -ErrorAction Stop

            Write-Debug -Message ('Module {0} imported.' -f $module)
        }
        catch
        {
            throw New-TerminatingError -ErrorType FailedToImportSqlModule -FormatArgs @($module) -ErrorCategory InvalidOperation -InnerException $_.Exception
        }
        finally
        {
            Write-Debug -Message 'Popping location back to what it was before importing SQLPS module.'
            Pop-Location
        }
    }
    else
    {
        throw New-TerminatingError -ErrorType SqlModuleNotFound -ErrorCategory InvalidOperation -InnerException $_.Exception
    }
}

<#
    .SYNOPSIS
    Restarts a SQL Server instance and associated services

    .PARAMETER SQLServer
    Hostname of the SQL Server to be configured

    .PARAMETER SQLInstanceName
    Name of the SQL instance to be configured. Default is 'MSSQLSERVER'

    .PARAMETER Timeout
    Timeout value for restarting the SQL services. The default value is 120 seconds.

    .EXAMPLE
    Restart-SqlService -SQLServer localhost

    .EXAMPLE
    Restart-SqlService -SQLServer localhost -SQLInstanceName 'NamedInstance'

    .EXAMPLE
    Restart-SqlService -SQLServer CLU01 -Timeout 300
#>
function Restart-SqlService
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $SQLServer,

        [Parameter()]
        [String]
        $SQLInstanceName = 'MSSQLSERVER',

        [Parameter()]
        [Int32]
        $Timeout = 120
    )

    ## Connect to the instance
    $serverObject = Connect-SQL -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName

    if ($serverObject.IsClustered)
    {
        ## Get the cluster resources
        New-VerboseMessage -Message 'Getting cluster resource for SQL Server'
        $sqlService = Get-CimInstance -Namespace root/MSCluster -ClassName MSCluster_Resource -Filter "Type = 'SQL Server'" |
                        Where-Object { $_.PrivateProperties.InstanceName -eq $serverObject.ServiceName }

        New-VerboseMessage -Message 'Getting active cluster resource SQL Server Agent'
        $agentService = $sqlService | Get-CimAssociatedInstance -ResultClassName MSCluster_Resource |
                            Where-Object { ($_.Type -eq "SQL Server Agent") -and ($_.State -eq 2) }

        ## Build a listing of resources being acted upon
        $resourceNames = @($sqlService.Name, ($agentService | Select-Object -ExpandProperty Name)) -join ","

        ## Stop the SQL Server and dependent resources
        New-VerboseMessage -Message "Bringing the SQL Server resources $resourceNames offline."
        $sqlService | Invoke-CimMethod -MethodName TakeOffline -Arguments @{ Timeout = $Timeout }

        ## Start the SQL server resource
        New-VerboseMessage -Message 'Bringing the SQL Server resource back online.'
        $sqlService | Invoke-CimMethod -MethodName BringOnline -Arguments @{ Timeout = $Timeout }

        ## Start the SQL Agent resource
        if ($agentService)
        {
            New-VerboseMessage -Message 'Bringing the SQL Server Agent resource online.'
            $agentService | Invoke-CimMethod -MethodName BringOnline -Arguments @{ Timeout = $Timeout }
        }
    }
    else
    {
        New-VerboseMessage -Message 'Getting SQL Service information'
        $sqlService = Get-Service -DisplayName "SQL Server ($($serverObject.ServiceName))"

        ## Get all dependent services that are running.
        ## There are scenarios where an automatic service is stopped and should not be restarted automatically.
        $agentService = $sqlService.DependentServices | Where-Object { $_.Status -eq "Running" }

        ## Restart the SQL Server service
        New-VerboseMessage -Message 'SQL Server service restarting'
        $sqlService | Restart-Service -Force

        ## Start dependent services
        $agentService | ForEach-Object {
            New-VerboseMessage -Message "Starting $($_.DisplayName)"
            $_ | Start-Service
        }
    }
}

<#
    .SYNOPSIS
    Executes a query on the specified database.

    .PARAMETER SQLServer
    The hostname of the server that hosts the SQL instance.

    .PARAMETER SQLInstanceName
    The name of the SQL instance that hosts the database.

    .PARAMETER Database
    Specify the name of the database to execute the query on.

    .PARAMETER Query
    The query string to execute.

    .PARAMETER WithResults
    Specifies if the query should return results.

    .EXAMPLE
    Invoke-Query -SQLServer Server1 -SQLInstanceName MSSQLSERVER -Database master -Query 'SELECT name FROM sys.databases' -WithResults

    .EXAMPLE
    Invoke-Query -SQLServer Server1 -SQLInstanceName MSSQLSERVER -Database master -Query 'RESTORE DATABASE [NorthWinds] WITH RECOVERY'
#>
function Invoke-Query
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SQLServer,

        [Parameter(Mandatory = $true)]
        [String]
        $SQLInstanceName,

        [Parameter(Mandatory = $true)]
        [String]
        $Database,

        [Parameter(Mandatory = $true)]
        [String]
        $Query,

        [Parameter()]
        [Switch]
        $WithResults
    )

    $serverObject = Connect-SQL -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName

    if ( $WithResults )
    {
        try
        {
            $result = $serverObject.Databases[$Database].ExecuteWithResults($Query)
        }
        catch
        {
            throw New-TerminatingError -ErrorType ExecuteQueryWithResultsFailed -FormatArgs $Database -ErrorCategory NotSpecified
        }
    }
    else
    {
        try
        {
            $serverObject.Databases[$Database].ExecuteNonQuery($Query)
        }
        catch
        {
            throw New-TerminatingError -ErrorType ExecuteNonQueryFailed -FormatArgs $Database -ErrorCategory NotSpecified
        }
    }

    return $result
}

<#
    .SYNOPSIS
        Executes the alter method on an Availability Group Replica object.

    .PARAMETER AvailabilityGroupReplica
        The Availability Group Replica object that must be altered.
#>
function Update-AvailabilityGroupReplica
{
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityReplica]
        $AvailabilityGroupReplica
    )

    try
    {
        $originalErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        $AvailabilityGroupReplica.Alter()
    }
    catch
    {
        throw New-TerminatingError -ErrorType AlterAvailabilityGroupReplicaFailed -FormatArgs $AvailabilityGroupReplica.Name -ErrorCategory OperationStopped
    }
    finally
    {
        $ErrorActionPreference = $originalErrorActionPreference
    }
}

function Test-LoginEffectivePermissions
{
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SQLServer,

        [Parameter(Mandatory = $true)]
        [String]
        $SQLInstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $LoginName,

        [Parameter(Mandatory = $true)]
        [string[]]
        $Permissions
    )

    # Assume the permissions are not present
    $permissionsPresent = $false

    $invokeQueryParams = @{
        SQLServer = $SQLServer
        SQLInstanceName = $SQLInstanceName
        Database = 'master'
        WithResults = $true
    }

    $queryToGetEffectivePermissionsForLogin = "
        EXECUTE AS LOGIN = '$LoginName'
        SELECT DISTINCT permission_name
        FROM fn_my_permissions(null,'SERVER')
        REVERT
    "

    New-VerboseMessage -Message "Getting the effective permissions for the login '$LoginName' on '$sqlInstanceName'."

    $loginEffectivePermissionsResult = Invoke-Query @invokeQueryParams -Query $queryToGetEffectivePermissionsForLogin
    $loginEffectivePermissions = $loginEffectivePermissionsResult.Tables.Rows.permission_name

    if ( $null -ne $loginEffectivePermissions )
    {
        $loginMissingPermissions = Compare-Object -ReferenceObject $Permissions -DifferenceObject $loginEffectivePermissions |
            Where-Object -FilterScript { $_.SideIndicator -ne '=>' } |
            Select-Object -ExpandProperty InputObject

        if ( $loginMissingPermissions.Count -eq 0 )
        {
            $permissionsPresent = $true
        }
    }

    return $permissionsPresent
}
