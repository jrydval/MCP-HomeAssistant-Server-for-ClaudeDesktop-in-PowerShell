# Home Assistant MCP Server using PowerShell
# Provides light and switch control for Claude Desktop
# Save as: mcp_home_assistant.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$HomeAssistantUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$ApiToken
)

# Array to store configuration
$config = @{
    url = $HomeAssistantUrl.TrimEnd('/')
    token = $ApiToken
    headers = @{
        "Authorization" = "Bearer $ApiToken"
        "Content-Type" = "application/json"
    }
}

# Logging function for debugging
function Write-MCPLog {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    [Console]::Error.WriteLine("$timestamp [HA-MCP] $Message")
    
    # Also log to file for persistent debugging
    $logFile = "/tmp/mcp_home_assistant.log"
    Add-Content -Path $logFile -Value "$timestamp [HA-MCP] $Message" -ErrorAction SilentlyContinue
}

# Function to send JSON-RPC response
function Send-JSONResponse {
    param([object]$Response)
    
    $jsonResponse = $Response | ConvertTo-Json -Depth 10 -Compress
    Write-MCPLog "Sending response: $jsonResponse"
    [Console]::WriteLine($jsonResponse)
    [Console]::Out.Flush()
}

# Helper function to get color name from RGB values
function Get-ColorName {
    param([int]$R, [int]$G, [int]$B)
    
    # Define common colors with tolerance
    $colors = @(
        @{ Name = "Red"; R = 255; G = 0; B = 0; Tolerance = 50 }
        @{ Name = "Green"; R = 0; G = 255; B = 0; Tolerance = 50 }
        @{ Name = "Blue"; R = 0; G = 0; B = 255; Tolerance = 50 }
        @{ Name = "White"; R = 255; G = 255; B = 255; Tolerance = 30 }
        @{ Name = "Yellow"; R = 255; G = 255; B = 0; Tolerance = 50 }
        @{ Name = "Purple"; R = 128; G = 0; B = 128; Tolerance = 60 }
        @{ Name = "Orange"; R = 255; G = 165; B = 0; Tolerance = 60 }
        @{ Name = "Pink"; R = 255; G = 192; B = 203; Tolerance = 60 }
        @{ Name = "Cyan"; R = 0; G = 255; B = 255; Tolerance = 50 }
        @{ Name = "Warm White"; R = 255; G = 244; B = 229; Tolerance = 40 }
    )
    
    foreach ($color in $colors) {
        $distance = [math]::Sqrt([math]::Pow($R - $color.R, 2) + [math]::Pow($G - $color.G, 2) + [math]::Pow($B - $color.B, 2))
        if ($distance -le $color.Tolerance) {
            return $color.Name
        }
    }
    
    return $null
}

# Function to call Home Assistant API
function Invoke-HomeAssistantAPI {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [object]$Body = $null
    )
    
    try {
        $uri = "$($config.url)/api/$Endpoint"
        Write-MCPLog "Calling HA API: $Method $uri"
        
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $config.headers
        }
        
        if ($Body) {
            $params.Body = $Body | ConvertTo-Json -Depth 10
            Write-MCPLog "Request body: $($params.Body)"
        }
        
        $response = Invoke-RestMethod @params
        Write-MCPLog "API response received successfully"
        return $response
    }
    catch {
        Write-MCPLog "API call failed: $($_.Exception.Message)"
        throw $_
    }
}

# Function to get entity states
function Get-EntityStates {
    param([string]$RequestId, [object]$Arguments)
    
    try {
        $entityPattern = $Arguments.entity_pattern
        if (-not $entityPattern) {
            $entityPattern = "(light\.|switch\.)"
        }
        
        Write-MCPLog "Getting entity states with pattern: $entityPattern"
        
        # Get areas (rooms) from Home Assistant
        $areas = @{}
        try {
            $areasResponse = Invoke-HomeAssistantAPI -Endpoint "config/area_registry"
            foreach ($area in $areasResponse) {
                $areas[$area.area_id] = @{
                    name = $area.name
                    entities = @()
                }
            }
            Write-MCPLog "Found $($areas.Count) areas/rooms in Home Assistant"
        }
        catch {
            Write-MCPLog "Could not fetch areas: $_"
            # Fallback to simple listing without areas
        }
        
        # Get devices and their area assignments
        $deviceToArea = @{}
        try {
            $devices = Invoke-HomeAssistantAPI -Endpoint "config/device_registry"
            foreach ($device in $devices) {
                if ($device.area_id) {
                    $deviceToArea[$device.id] = $device.area_id
                }
            }
            Write-MCPLog "Found $($devices.Count) devices"
        }
        catch {
            Write-MCPLog "Could not fetch device registry: $_"
        }
        
        # Get entity registry to map entities to devices/areas
        $entityToArea = @{}
        try {
            $entities = Invoke-HomeAssistantAPI -Endpoint "config/entity_registry"
            foreach ($entity in $entities) {
                # Direct area assignment
                if ($entity.area_id) {
                    $entityToArea[$entity.entity_id] = $entity.area_id
                }
                # Area via device
                elseif ($entity.device_id -and $deviceToArea[$entity.device_id]) {
                    $entityToArea[$entity.entity_id] = $deviceToArea[$entity.device_id]
                }
            }
            Write-MCPLog "Mapped $($entityToArea.Count) entities to areas"
        }
        catch {
            Write-MCPLog "Could not fetch entity registry: $_"
        }
        
        # Get current states
        $states = Invoke-HomeAssistantAPI -Endpoint "states"
        
        # Filter and organize entities by area
        $filteredEntities = $states | Where-Object { 
            $_.entity_id -match $entityPattern 
        }
        
        # Group entities by their assigned areas
        foreach ($entity in $filteredEntities) {
            $areaId = $entityToArea[$entity.entity_id]
            
            $entityInfo = @{
                entity_id = $entity.entity_id
                state = $entity.state
                friendly_name = $entity.attributes.friendly_name
                brightness = $entity.attributes.brightness
                color_temp = $entity.attributes.color_temp
                rgb_color = $entity.attributes.rgb_color
                device_class = $entity.attributes.device_class
                last_changed = $entity.last_changed
            }
            
            if ($areaId -and $areas[$areaId]) {
                # Add to specific area
                $areas[$areaId].entities += $entityInfo
            } else {
                # Add to "Unassigned" area
                if (-not $areas["unassigned"]) {
                    $areas["unassigned"] = @{
                        name = "Unassigned"
                        entities = @()
                    }
                }
                $areas["unassigned"].entities += $entityInfo
            }
        }
        
        # Build result text organized by rooms
        $resultText = "Found $($filteredEntities.Count) entities matching pattern '$entityPattern':`n"
        
        # Sort areas by name and show only those with entities
        $areasWithEntities = $areas.Values | Where-Object { $_.entities.Count -gt 0 } | Sort-Object name
        
        foreach ($area in $areasWithEntities) {
            $resultText += "`n🏠 **$($area.name)**:`n"
            
            # Sort entities within area by friendly name
            $sortedEntities = $area.entities | Sort-Object friendly_name
            
            foreach ($entity in $sortedEntities) {
                $resultText += "  • $($entity.friendly_name) ($($entity.entity_id)): $($entity.state)"
                
                # Add brightness info for lights
                if ($entity.brightness) {
                    $brightnessPct = [math]::Round(($entity.brightness / 255) * 100)
                    $resultText += " (Brightness: $brightnessPct%)"
                }
                
                # Add RGB color info if available
                if ($entity.rgb_color -and $entity.rgb_color.Count -eq 3) {
                    $r = $entity.rgb_color[0]
                    $g = $entity.rgb_color[1] 
                    $b = $entity.rgb_color[2]
                    $resultText += " (RGB: $r,$g,$b)"
                    
                    # Add color name hint for common colors
                    $colorName = Get-ColorName -R $r -G $g -B $b
                    if ($colorName) {
                        $resultText += " [$colorName]"
                    }
                }
                
                # Add color temperature if available (and no RGB)
                elseif ($entity.color_temp) {
                    $resultText += " (Color Temp: $($entity.color_temp) mireds)"
                }
                
                # Add device class if available
                if ($entity.device_class) {
                    $resultText += " [$($entity.device_class)]"
                }
                
                $resultText += "`n"
            }
        }
        
        if ($filteredEntities.Count -eq 0) {
            $resultText = "No entities found matching pattern '$entityPattern'"
        }
        
        Send-JSONResponse @{
            jsonrpc = "2.0"
            id = $RequestId
            result = @{
                content = @(
                    @{
                        type = "text"
                        text = $resultText
                    }
                )
            }
        }
    }
    catch {
        Write-MCPLog "Error getting entity states: $_"
        Send-JSONResponse @{
            jsonrpc = "2.0"
            id = $RequestId
            error = @{
                code = -32603
                message = "Failed to get entity states: $($_.Exception.Message)"
            }
        }
    }
}

# Function to control lights
function Set-LightState {
    param([string]$RequestId, [object]$Arguments)
    
    try {
        $entityId = $Arguments.entity_id
        $state = $Arguments.state
        $brightness = $Arguments.brightness
        $colorTemp = $Arguments.color_temp
        $rgbColor = $Arguments.rgb_color
        
        if (-not $entityId) {
            Send-JSONResponse @{
                jsonrpc = "2.0"
                id = $RequestId
                error = @{
                    code = -32602
                    message = "entity_id parameter is required"
                }
            }
            return
        }
        
        Write-MCPLog "Setting light state: $entityId to $state"
        
        # Determine service to call
        $service = if ($state -eq "on") { "light/turn_on" } else { "light/turn_off" }
        
        # Build service data
        $serviceData = @{
            entity_id = $entityId
        }
        
        # Add optional parameters for turn_on
        if ($state -eq "on") {
            if ($brightness) { $serviceData.brightness = [int]$brightness }
            if ($colorTemp) { $serviceData.color_temp = [int]$colorTemp }
            if ($rgbColor) { $serviceData.rgb_color = $rgbColor }
        }
        
        # Call Home Assistant service
        $response = Invoke-HomeAssistantAPI -Endpoint "services/$service" -Method "POST" -Body $serviceData
        
        $resultText = "Successfully set $entityId to $state"
        if ($brightness -and $state -eq "on") {
            $resultText += " with brightness $brightness"
        }
        
        Send-JSONResponse @{
            jsonrpc = "2.0"
            id = $RequestId
            result = @{
                content = @(
                    @{
                        type = "text"
                        text = $resultText
                    }
                )
            }
        }
    }
    catch {
        Write-MCPLog "Error setting light state: $_"
        Send-JSONResponse @{
            jsonrpc = "2.0"
            id = $RequestId
            error = @{
                code = -32603
                message = "Failed to set light state: $($_.Exception.Message)"
            }
        }
    }
}

# Function to control switches
function Set-SwitchState {
    param([string]$RequestId, [object]$Arguments)
    
    try {
        $entityId = $Arguments.entity_id
        $state = $Arguments.state
        
        if (-not $entityId -or -not $state) {
            Send-JSONResponse @{
                jsonrpc = "2.0"
                id = $RequestId
                error = @{
                    code = -32602
                    message = "entity_id and state parameters are required"
                }
            }
            return
        }
        
        Write-MCPLog "Setting switch state: $entityId to $state"
        
        # Determine service to call
        $service = if ($state -eq "on") { "switch/turn_on" } else { "switch/turn_off" }
        
        # Build service data
        $serviceData = @{
            entity_id = $entityId
        }
        
        # Call Home Assistant service
        $response = Invoke-HomeAssistantAPI -Endpoint "services/$service" -Method "POST" -Body $serviceData
        
        Send-JSONResponse @{
            jsonrpc = "2.0"
            id = $RequestId
            result = @{
                content = @(
                    @{
                        type = "text"
                        text = "Successfully set $entityId to $state"
                    }
                )
            }
        }
    }
    catch {
        Write-MCPLog "Error setting switch state: $_"
        Send-JSONResponse @{
            jsonrpc = "2.0"
            id = $RequestId
            error = @{
                code = -32603
                message = "Failed to set switch state: $($_.Exception.Message)"
            }
        }
    }
}

# Function to handle initialize request
function Handle-Initialize {
    param([object]$Params, [string]$RequestId)
    
    $protocolVersion = if ($Params.protocolVersion) { $Params.protocolVersion } else { "2024-11-05" }
    
    Send-JSONResponse @{
        jsonrpc = "2.0"
        id = $RequestId
        result = @{
            protocolVersion = $protocolVersion
            capabilities = @{
                tools = @{
                    listChanged = $true
                }
                logging = @{}
                prompts = @{}
                resources = @{}
            }
            serverInfo = @{
                name = "Home Assistant MCP Server"
                version = "1.0.0"
            }
        }
    }
}

# Function to handle tools/list request
function Handle-ToolsList {
    param([string]$RequestId)
    
    Send-JSONResponse @{
        jsonrpc = "2.0"
        id = $RequestId
        result = @{
            tools = @(
                @{
                    name = "get_entity_states"
                    description = "Get current states of Home Assistant entities (lights and switches) with location information"
                    inputSchema = @{
                        type = "object"
                        properties = @{
                            entity_pattern = @{
                                type = "string"
                                description = "Regex pattern to filter entities (default: light.* and switch.*)"
                                default = "(light\.|switch\.)"
                            }
                        }
                    }
                }
                @{
                    name = "set_light_state"
                    description = "Control Home Assistant lights (turn on/off, set brightness, color)"
                    inputSchema = @{
                        type = "object"
                        properties = @{
                            entity_id = @{
                                type = "string"
                                description = "Light entity ID (e.g., light.living_room)"
                            }
                            state = @{
                                type = "string"
                                enum = @("on", "off")
                                description = "Desired state of the light"
                            }
                            brightness = @{
                                type = "integer"
                                minimum = 0
                                maximum = 255
                                description = "Brightness level (0-255, only for turn_on)"
                            }
                            color_temp = @{
                                type = "integer"
                                description = "Color temperature in mireds"
                            }
                            rgb_color = @{
                                type = "array"
                                items = @{ type = "integer"; minimum = 0; maximum = 255 }
                                minItems = 3
                                maxItems = 3
                                description = "RGB color [red, green, blue] (0-255 each)"
                            }
                        }
                        required = @("entity_id", "state")
                    }
                }
                @{
                    name = "set_switch_state"
                    description = "Control Home Assistant switches (turn on/off)"
                    inputSchema = @{
                        type = "object"
                        properties = @{
                            entity_id = @{
                                type = "string"
                                description = "Switch entity ID (e.g., switch.coffee_maker)"
                            }
                            state = @{
                                type = "string"
                                enum = @("on", "off")
                                description = "Desired state of the switch"
                            }
                        }
                        required = @("entity_id", "state")
                    }
                }
            )
        }
    }
}

# Function to handle tools/call request
function Handle-ToolsCall {
    param([object]$Params, [string]$RequestId)
    
    $toolName = $Params.name
    $arguments = $Params.arguments
    
    switch ($toolName) {
        "get_entity_states" {
            Get-EntityStates -RequestId $RequestId -Arguments $arguments
        }
        "set_light_state" {
            Set-LightState -RequestId $RequestId -Arguments $arguments
        }
        "set_switch_state" {
            Set-SwitchState -RequestId $RequestId -Arguments $arguments
        }
        default {
            Send-JSONResponse @{
                jsonrpc = "2.0"
                id = $RequestId
                error = @{
                    code = -32601
                    message = "Tool '$toolName' not found"
                }
            }
        }
    }
}

# Validate configuration at startup
Write-MCPLog "Home Assistant MCP Server starting..."
Write-MCPLog "Home Assistant URL: $($config.url)"

try {
    # Test connection to Home Assistant
    $testResponse = Invoke-HomeAssistantAPI -Endpoint "states"
    Write-MCPLog "Successfully connected to Home Assistant. Found $($testResponse.Count) entities."
}
catch {
    Write-MCPLog "Failed to connect to Home Assistant: $_"
    Write-MCPLog "Please check your URL and API token"
}

Write-MCPLog "Available tools: get_entity_states, set_light_state, set_switch_state"
Write-MCPLog "Waiting for JSON-RPC messages on stdin..."

# Main message processing loop
try {
    while ($true) {
        $line = [Console]::ReadLine()
        
        if ($null -eq $line) {
            Write-MCPLog "EOF received, shutting down"
            break
        }
        
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        
        Write-MCPLog "Received: $line"
        
        try {
            $request = $line | ConvertFrom-Json
            $method = $request.method
            $params = $request.params
            $id = $request.id
            
            Write-MCPLog "Processing method: $method (id: $id)"
            
            switch ($method) {
                "initialize" {
                    Write-MCPLog "Handling initialize request"
                    Handle-Initialize -Params $params -RequestId $id
                }
                "initialized" {
                    Write-MCPLog "Received initialized notification"
                }
                "notifications/initialized" {
                    Write-MCPLog "Received initialized notification (full path)"
                }
                "tools/list" {
                    Write-MCPLog "Handling tools/list request"
                    Handle-ToolsList -RequestId $id
                }
                "tools/call" {
                    Write-MCPLog "Handling tools/call request for tool: $($params.name)"
                    Handle-ToolsCall -Params $params -RequestId $id
                }
                default {
                    Write-MCPLog "Unknown method: $method"
                    if ($id) {
                        Send-JSONResponse @{
                            jsonrpc = "2.0"
                            id = $id
                            error = @{
                                code = -32601
                                message = "Method not found: $method"
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-MCPLog "Error parsing request: $_"
            Send-JSONResponse @{
                jsonrpc = "2.0"
                id = $null
                error = @{
                    code = -32700
                    message = "Parse error: $($_.Exception.Message)"
                }
            }
        }
    }
}
catch {
    Write-MCPLog "Fatal error: $_"
}
finally {
    Write-MCPLog "Home Assistant MCP Server shutting down"
}