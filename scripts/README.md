# Q-SYS NMOS Crosspoint Router Control Script

## Overview

This Lua script provides a comprehensive interface for controlling an NMOS Crosspoint Router directly from Q-SYS via WebSocket API. It enables real-time discovery, monitoring, and control of NMOS-compliant media devices on your network.

## Features

- **Real-time WebSocket Communication**: Direct connection to NMOS Crosspoint Router
- **Device Discovery**: Automatic discovery of NMOS senders, receivers, and flows
- **Crosspoint Control**: Make and break connections between encoders and decoders
- **Authentication Support**: Secure authentication with SHA256 password hashing
- **JSON Preset Support**: Load and save connection configurations via JSON
- **Visual Status Monitoring**: Real-time device and connection status display
- **Automatic Reconnection**: Robust connection handling with automatic retry
- **Debug Logging**: Comprehensive logging for troubleshooting

## Prerequisites

- Q-SYS Designer software
- NMOS Crosspoint Router (server) running and accessible
- Network connectivity between Q-SYS Core and NMOS Router
- WebSocket access enabled on NMOS Router (default port 80)

## Installation

1. **Add Script to Q-SYS Designer**:
   - Open your Q-SYS design file
   - Add a "Control Script" component
   - Copy and paste the contents of `q-sys-crosspoint-control.lua`

2. **Create Required Controls**:
   - `Controls["IP Address"]` (String): IP address of NMOS Crosspoint Router
   - `Controls["Connection status"]` (String): Connection status display
   - `Controls["CIP-Status"]` (String): Matrox CIP status (optional)
   - `Controls["Encoder"]` (String or Array): Encoder device names (comma-separated or array)

3. **Create Decoder Controls**:
   - `Controls.Decoder` (Array of String): Decoder device names
   - `Controls.DecoderSource` (Array of String/Knob/Combo): Source selection for each decoder
   - `Controls.Multiviewer` (Array of Boolean): Per-decoder multiviewer toggle controls

4. **Optional Controls**:
   - `Controls.Code` (String): JSON preset input for advanced commands

## Configuration

### Basic Settings

```lua
-- Router credentials (modify as needed)
ROUTER_USER = "admin"
ROUTER_PASSWORD = "password"

-- Debug and monitoring flags
DEBUG_ENABLED = false      -- Set true for verbose logging
ENABLE_PATCH_STATS = false -- Set true for patch statistics

-- Network configuration
ROUTER_PORT = 80           -- WebSocket port (default 80)
RECONNECT_INTERVAL = 5     -- Seconds between reconnect attempts
MAX_RECONNECT_INTERVAL = 60 -- Maximum reconnect interval
```

### Network Configuration

1. Set the IP address in `Controls["IP Address"]` to your NMOS Router server
2. Ensure proper network routing between Q-SYS Core and NMOS Router
3. Configure firewall rules to allow WebSocket connections (default port 80)
4. Configure encoder names in `Controls["Encoder"]` (comma-separated string or array)
5. Set up decoder names in the `Controls.Decoder` array

## Usage

### Connection Process

1. **Initial Connection**: The script automatically attempts to connect when loaded
2. **Authentication**: Uses SHA256 password hashing with server-provided seed
3. **Channel Subscription**: Subscribes to `mediadevices` and `mediadevmatroxcip` channels
4. **Real-time Updates**: Receives patch-based updates for device state changes
5. **Automatic Reconnection**: Implements exponential backoff for failed connections

### Making Connections

#### Method 1: Manual Control
- Use the `Controls.DecoderSource` dropdowns to select sources for each decoder
- Changes are automatically sent to the NMOS Router

#### Method 2: JSON Presets
- Use `Controls.Code` (String) to input JSON connection commands
- Format: JSON array of connection objects

**Example JSON Preset**:
```json
{
  "method": "POST",
  "route": "/makeconnection",
  "data": {
    "source": "encoder_name",
    "destination": "decoder_name"
  }
}
```

### Matrox Convert IP Multiviewer Control

The script provides comprehensive multiviewer control for Matrox Convert IP devices:

- **Per-Decoder Toggles**: Each decoder has its own multiviewer toggle (`Controls.Multiviewer[n]`)
- **Automatic Master Mode**: When multiviewer is enabled, master mode is automatically activated
- **Device Identification**: Supports device lookup by serial number, device name, or alias
- **WebSocket API Integration**: Uses crosspoint router API instead of direct device HTTP calls
- **Multiple Connection Methods**: Supports both postfix channel and flow type notation

##### Multiviewer Connection Methods

The script provides multiple ways to connect encoders to multiviewer decoders:

**Method 1: Postfix Channel Numbers (Simple)**
```lua
-- Connect encoders to specific multiviewer channels
ConnectToMultiviewer({"Encoder1", "Encoder2", "Encoder3"}, "CIP-DEC-740", 1)
-- Result: Encoder1→CIP-DEC-740.1, Encoder2→CIP-DEC-740.2, Encoder3→CIP-DEC-740.3
```

**Method 2: Flow Type Notation (Advanced)**
```lua
-- Connect encoders using NMOS flow type notation
ConnectToMultiviewerFlows({"Encoder1", "Encoder2"}, "CIP-DEC-740", "v", 1)
-- Result: Encoder1→CIP-DEC-740.v1, Encoder2→CIP-DEC-740.v2

-- Audio flows
ConnectToMultiviewerFlows({"AudioEnc1", "AudioEnc2"}, "CIP-DEC-740", "a", 1)
-- Result: AudioEnc1→CIP-DEC-740.a1, AudioEnc2→CIP-DEC-740.a2
```

**Method 3: Complete Multiviewer Setup**
```lua
-- Enable multiviewer and connect encoders in one step
SetupMultiviewer("CIP-DEC-740", {"Enc1", "Enc2", "Enc3", "Enc4"}, {
  startChannel = 1,
  useFlowType = false,  -- Use postfix notation
  enableFirst = true    -- Enable multiviewer mode first
})

-- Advanced setup with flow type notation
SetupMultiviewer("CIP-DEC-740", {"Enc1", "Enc2"}, {
  startChannel = 1,
  useFlowType = true,
  flowType = "v",
  enableFirst = true
})
```

**Method 4: JSON Preset (Batch Operations)**
```json
{
  "method": "POST", 
  "route": "makeconnection",
  "data": {
    "multiple": [
      {"source": "Encoder1", "destination": "CIP-DEC-740.1"},
      {"source": "Encoder2", "destination": "CIP-DEC-740.2"},
      {"source": "Encoder3", "destination": "CIP-DEC-740.3"},
      {"source": "Encoder4", "destination": "CIP-DEC-740.4"}
    ]
  }
}
```

##### Channel Notation Formats

| Format | Example | Description |
|--------|---------|-------------|
| Postfix Numbers | `CIP-DEC-740.1` | Simple channel numbers (1, 2, 3, 4...) |
| Video Flows | `CIP-DEC-740.v1` | NMOS video flow notation |
| Audio Flows | `CIP-DEC-740.a1` | NMOS audio flow notation |
| Data Flows | `CIP-DEC-740.d1` | NMOS data flow notation |

**Debug Output**: Enable debug logging to see detailed multiviewer operation logs including device lookup, API calls, and status changes.

**Troubleshooting**:
- Verify device is reachable and has multiviewer license installed
- Check WebSocket connection status
- Enable debug logging for detailed operation tracking
- Ensure correct device serial number/name in decoder controls
- For batch connections, verify all encoder names are valid

### Supported Commands

- **Individual Connections**: Select encoder for each decoder via `Controls.DecoderSource` dropdowns
- **Disconnect**: Select "-- DISCONNECT --" option to clear decoder connection
- **JSON Presets**: Use `Controls.Code` for batch operations and complex routing
- **Multiviewer Toggle**: Per-decoder multiviewer enable/disable via `Controls.Multiviewer` array
- **Batch Multiviewer**: Use `ConnectToMultiviewer()`, `ConnectToMultiviewerFlows()`, or `SetupMultiviewer()` functions

## API Integration

### WebSocket Messages

The script handles several message types from the NMOS Router:

- **authseed**: Server-provided seed for SHA256 password hashing
- **authok**: Successful authentication confirmation
- **sync**: Initial data synchronization for subscribed channels
- **patch**: Incremental JSON Patch updates to device state
- **response**: Server responses to API requests
- **ping/pong**: Keep-alive messages
- **authfailed/autherror**: Authentication failure notifications

### Data Structures

#### Device Information
```lua
stored_device_data = {
  devices = {
    [device_id] = {
      name = "device_name",
      type = "encoder|decoder",
      state = "connected|disconnected",
      flows = {...}
    }
  }
}
```

#### Connection Commands
```lua
{
  method = "POST",
  route = "/makeconnection",
  data = {
    source = "encoder_device_id",
    destination = "decoder_device_id"
  }
}
```

## Troubleshooting

### Connection Issues

1. **Check IP Address**: Verify `Controls["IP Address"]` is correct
2. **Network Connectivity**: Test ping from Q-SYS Core to NMOS Router
3. **WebSocket Port**: Ensure port 80 (or configured port) is accessible
4. **Authentication**: Verify username/password in script configuration

### Debug Logging

Enable debug logging by setting:
```lua
DEBUG_ENABLED = true
```

This will provide verbose output in Q-SYS logs for troubleshooting.

### Common Error Messages

- **"Failed to decode JSON"**: Check network connectivity and server response
- **"Authentication failed"**: Verify credentials in `ROUTER_USER` and `ROUTER_PASSWORD`
- **"Connection timeout"**: Check firewall and network routing to port 80
- **"Control 'X' not found"**: Ensure required Q-SYS controls are created
- **"IP Address control is empty"**: Set the router IP address in the control

### Device Discovery Issues

1. **No devices found**: Check `mediadevices` and `mediadevmatroxcip` subscriptions
2. **Missing encoder names**: Configure `Controls["Encoder"]` with device names
3. **Decoder control mismatch**: Ensure `Controls.Decoder` and `Controls.DecoderSource` arrays match
4. **Stale device list**: Check patch processing and UI update throttling

### Matrox Convert IP Multiviewer Issues

1. **Multiviewer toggle not working**: Verify `Controls.Multiviewer` array exists and matches decoder count
2. **Device not found errors**: Check device serial number formats and ensure device is discoverable
3. **Master mode not activating**: Verify automatic master mode enable is working (check debug logs)
4. **API authentication failures**: Confirm Matrox device credentials are correct in backend
5. **Multiviewer license not installed**: Check device capabilities and license status

## Advanced Configuration

### Custom Device Mapping

The script reads encoder names from `Controls["Encoder"]` and supports:

```lua
-- Option 1: Comma-separated string in single control
Controls["Encoder"].String = "Studio_Encoder,Remote_Encoder,Backup_Encoder"

-- Option 2: Array of encoder controls
Controls["Encoder"][1].String = "Studio_Encoder"
Controls["Encoder"][2].String = "Remote_Encoder"

-- Decoder controls are automatically mapped from arrays
-- Controls.Decoder[1].String, Controls.DecoderSource[1], etc.
```

### Custom Authentication

For custom authentication schemes, modify the authentication handler:

```lua
-- Custom authentication response generation
local function customAuthResponse(seed)
  -- Implement custom authentication logic here
  return custom_hash_function(seed)
end
```

### Integration with External Systems

The script can be extended to integrate with:
- External control systems
- Custom automation workflows
- Third-party monitoring tools

## Performance Considerations

### Network Optimization
- Use wired connections for Q-SYS Core when possible
- Minimize network hops between Q-SYS and NMOS Router
- Configure appropriate ping intervals (default 30 seconds) for keep-alive
- Monitor exponential backoff reconnection behavior

### Memory Management
- The script uses patch-based updates to minimize memory usage
- UI updates are throttled (0.5s interval) to prevent excessive processing
- Device data is stored in `stored_device_data` table with automatic cleanup
- Enable `ENABLE_PATCH_STATS` for monitoring patch operation statistics

## Security Considerations

### Authentication
- Use strong passwords for NMOS Router access
- Consider using certificate-based authentication if supported
- Regularly update credentials and review access logs

### Network Security
- Use VPN or secure network segments for remote access
- Configure firewall rules to limit access to necessary ports only
- Monitor WebSocket connections for unusual activity

## Support and Maintenance

### Regular Maintenance
- Monitor connection logs for errors or warnings
- Update script configuration when network changes occur
- Test backup and recovery procedures regularly

### Version Updates
- Check for script updates and security patches
- Test updates in non-production environment first
- Document any custom modifications for future reference

## Contact and Support

For technical support:
- Check Q-SYS logs for detailed error messages
- Review NMOS Router server logs for connection issues
- Consult NMOS Crosspoint Router documentation
- Contact system administrator for network-related issues

## License and Usage

This script is provided as-is for use with Q-SYS systems. Ensure compliance with your organization's software policies and security requirements before deployment.
