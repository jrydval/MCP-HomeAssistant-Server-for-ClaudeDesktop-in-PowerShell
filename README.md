# Home Assistant MCP Server

A Model Context Protocol (MCP) server that allows Claude Desktop to control your Home Assistant smart home devices. Control lights, switches, and monitor device states directly from Claude conversations.

<img width="753" height="681" alt="image" src="https://github.com/user-attachments/assets/a957f2e5-05ed-4d09-b9e1-31b07bfab74d" />


## Features

🏠 **Smart Home Control**
- Get status of all lights and switches organized by rooms
- Turn lights on/off with brightness and color control  
- Control switches and smart plugs
- Real-time device state monitoring with RGB color information
- Automatic room/area detection from Home Assistant configuration

🔧 **Easy Integration**
- Simple PowerShell implementation
- Secure API token authentication
- Comprehensive error handling and logging
- Works with any Home Assistant installation
- Uses official Home Assistant Areas for room organization

## Available Tools

### `get_entity_states`
Retrieve current states of Home Assistant entities (lights and switches) organized by rooms/areas.

**Parameters:**
- `entity_pattern` (string, optional) - Regex pattern to filter entities (default: matches `light.*` and `switch.*`)

**Returns:**
- Entity states grouped by Home Assistant Areas (rooms)
- Brightness percentages for lights
- RGB color values and color names for smart bulbs
- Color temperature information
- Device classes and other attributes
- Friendly names and entity IDs

**Example output:**
```
Found 8 entities matching pattern '(light\.|switch\.)':

🏠 **Living Room**:
  • RGB Strip (light.rgb_strip): on (Brightness: 80%) (RGB: 255,0,128) [Pink]
  • Main Light (light.living_room_main): on (Brightness: 75%) (Color Temp: 370 mireds)
  • TV Switch (switch.living_room_tv): on

🏠 **Kitchen**:
  • Kitchen Lights (light.kitchen): on (Brightness: 100%) (RGB: 255,255,255) [White]
  • Coffee Maker (switch.coffee_maker): off [outlet]

🏠 **Unassigned**:
  • Garden Light (light.garden): off
```

**Example:**
```json
{
  "name": "get_entity_states",
  "arguments": {
    "entity_pattern": "light.living_room.*"
  }
}
```

### `set_light_state`
Control Home Assistant lights with full feature support including RGB colors.

**Parameters:**
- `entity_id` (string, required) - Light entity ID (e.g., `light.living_room`)
- `state` (string, required) - Either "on" or "off"
- `brightness` (integer, optional) - Brightness level 0-255 (only for "on" state)
- `color_temp` (integer, optional) - Color temperature in mireds
- `rgb_color` (array, optional) - RGB color as [red, green, blue] (0-255 each)

**Examples:**
```json
{
  "name": "set_light_state",
  "arguments": {
    "entity_id": "light.living_room",
    "state": "on",
    "brightness": 128
  }
}
```

```json
{
  "name": "set_light_state",
  "arguments": {
    "entity_id": "light.rgb_strip",
    "state": "on",
    "rgb_color": [255, 0, 0],
    "brightness": 200
  }
}
```

### `set_switch_state`
Control Home Assistant switches and smart plugs.

**Parameters:**
- `entity_id` (string, required) - Switch entity ID (e.g., `switch.coffee_maker`)
- `state` (string, required) - Either "on" or "off"

**Example:**
```json
{
  "name": "set_switch_state",
  "arguments": {
    "entity_id": "switch.coffee_maker",
    "state": "on"
  }
}
```

## Setup

### Prerequisites

1. **Home Assistant** running and accessible
2. **PowerShell** 7.0+ (`pwsh`)
3. **Claude Desktop** with MCP support
4. **Long-Lived Access Token** from Home Assistant

### Step 1: Create Home Assistant Access Token

1. Log into your Home Assistant web interface
2. Go to **Profile** → **Security** → **Long-lived access tokens**
3. Click **Create Token**
4. Give it a name like "Claude Desktop MCP"
5. Copy the generated token (you won't see it again!)

### Step 2: Configure Areas in Home Assistant (Optional but Recommended)

For the best experience, assign your devices to Areas in Home Assistant:

1. Go to **Settings** → **Devices & Services** → **Areas & Labels**
2. Create areas for your rooms (e.g., "Living Room", "Kitchen", "Bedroom")
3. Go to **Settings** → **Devices & Services** → **Devices**
4. For each device, click on it and assign it to the appropriate area
5. Alternatively, assign entities directly to areas in **Settings** → **Devices & Services** → **Entities**

### Step 3: Download and Configure

1. **Download the server:**
   ```bash
   curl -O https://raw.githubusercontent.com/YOUR_USERNAME/home-assistant-mcp/main/mcp_home_assistant.ps1
   ```

2. **Configure Claude Desktop:**
   Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "Home Assistant": {
         "command": "pwsh",
         "args": [
           "-File",
           "/path/to/mcp_home_assistant.ps1",
           "-HomeAssistantUrl",
           "http://YOUR_HA_IP:8123",
           "-ApiToken",
           "YOUR_LONG_LIVED_TOKEN"
         ],
         "env": {}
       }
     }
   }
   ```

3. **Update the configuration:**
   - Replace `/path/to/mcp_home_assistant.ps1` with actual file path
   - Replace `YOUR_HA_IP:8123` with your Home Assistant URL
   - Replace `YOUR_LONG_LIVED_TOKEN` with your access token

4. **Restart Claude Desktop** completely (Quit + restart)

## Testing

### Test the Server Manually
```bash
# Test server connection
pwsh -File mcp_home_assistant.ps1 -HomeAssistantUrl "http://homeassistant.local:8123" -ApiToken "your_token"

# Test with JSON-RPC (in another terminal)
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}' | pwsh -File mcp_home_assistant.ps1 -HomeAssistantUrl "http://homeassistant.local:8123" -ApiToken "your_token"
```

### Test Individual Tools
```bash
# Get entity states
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_entity_states","arguments":{}}}' | pwsh -File mcp_home_assistant.ps1 -HomeAssistantUrl "http://homeassistant.local:8123" -ApiToken "your_token"

# Turn on a light with RGB color
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"set_light_state","arguments":{"entity_id":"light.living_room","state":"on","rgb_color":[255,0,0],"brightness":128}}}' | pwsh -File mcp_home_assistant.ps1 -HomeAssistantUrl "http://homeassistant.local:8123" -ApiToken "your_token"
```

## Usage Examples

Once configured, you can control your smart home directly in Claude conversations:

**"Show me all lights in the house"**
- Claude will use `get_entity_states` to list all lights organized by rooms

**"Turn on the living room lights to 50% brightness"**
- Claude will use `set_light_state` with brightness 128 (50% of 255)

**"Set the bedroom lights to red"**
- Claude will use `set_light_state` with rgb_color [255, 0, 0]

**"Turn off the coffee maker"**
- Claude will use `set_switch_state` to turn off the switch

**"What color are the kitchen lights?"**
- Claude will check the state and show RGB values and color name

**"Turn on all lights in the living room"**
- After checking current states, Claude can control multiple lights

## Supported Color Information

The server recognizes and displays these colors:
- **Red** (255,0,0)
- **Green** (0,255,0)
- **Blue** (0,0,255)
- **White** (255,255,255)
- **Yellow** (255,255,0)
- **Purple** (128,0,128)
- **Orange** (255,165,0)
- **Pink** (255,192,203)
- **Cyan** (0,255,255)
- **Warm White** (255,244,229)

Colors are detected with tolerance, so slight variations will still be recognized.

## Debugging

### Server Logs
```bash
# Watch MCP server logs in real-time
tail -f /tmp/mcp_home_assistant.log

# Or check stderr when running manually
pwsh -File mcp_home_assistant.ps1 -HomeAssistantUrl "..." -ApiToken "..."
```

### Claude Desktop Logs
```bash
# On macOS - MCP server specific log
tail -f ~/Library/Logs/Claude/

# Watch for your specific MCP server logs
ls ~/Library/Logs/Claude/mcp-server-*

# Or use Console.app and filter by "Claude"
```

### Troubleshooting

1. **"Failed to connect to Home Assistant"**
   - Check URL format: `http://IP:8123` (no trailing slash)
   - Verify Home Assistant is accessible from your machine
   - Test with: `curl http://YOUR_HA_IP:8123/api/states -H "Authorization: Bearer YOUR_TOKEN"`

2. **"Invalid API token"**
   - Regenerate the Long-Lived Access Token in Home Assistant
   - Ensure no extra spaces in the token
   - Check token permissions in Home Assistant

3. **"Entity not found"**
   - Use `get_entity_states` to see available entities
   - Check entity IDs are exactly as shown in Home Assistant
   - Entity IDs are case-sensitive

4. **Tools not appearing in Claude Desktop**
   - Restart Claude Desktop completely
   - Check Claude Desktop logs in `~/Library/Logs/Claude/`
   - Verify file paths in configuration
   - Look for your MCP server log file: `mcp-server-Home Assistant.log`

5. **Entities showing as "Unassigned"**
   - Assign devices/entities to Areas in Home Assistant
   - Go to Settings → Devices & Services → Areas & Labels
   - Create areas and assign your devices to them

6. **RGB colors not showing**
   - Not all lights support RGB colors
   - Check if your lights support `rgb_color` attribute in Home Assistant
   - Some lights only support color temperature

## Home Assistant Configuration Tips

### Setting Up Areas
1. **Create meaningful area names** - use room names like "Living Room", "Kitchen"
2. **Assign devices to areas** when adding new integrations
3. **Use consistent naming** - avoid special characters in area names
4. **Group related devices** - put all living room lights in the "Living Room" area

### Entity Naming Best Practices
1. **Use descriptive friendly names** - "Living Room Main Light" instead of "Light 1"
2. **Be consistent** - use the same pattern across similar devices
3. **Include location** in the name if not using areas

## Security Notes

- **Keep your API token secure** - it provides full access to your Home Assistant
- **Use HTTPS** if accessing Home Assistant over the internet
- **Consider network isolation** for smart home devices
- **Regularly rotate access tokens**
- **Monitor access logs** in Home Assistant

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Update documentation
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- Built for [Claude Desktop](https://claude.ai/desktop) by Anthropic
- Uses the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
- Integrates with [Home Assistant](https://www.home-assistant.io/)
- RGB color detection inspired by common smart bulb implementations

---

**Happy smart home automation with Claude! 🏠🤖🌈**
