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

The script provides integrated control for Matrox Convert IP device multiviewer functionality:

#### Per-Decoder Multiviewer Controls
- Each decoder has its own `Controls.Multiviewer[n]` (Boolean) toggle
- Toggling enables/disables multiviewer mode for the specific decoder
- When multiviewer is enabled, master mode is automatically activated
- Changes are sent via WebSocket API to the NMOS Crosspoint Router

#### Automatic Master Mode Activation
- Master mode is automatically enabled when multiviewer is activated
- Ensures proper operation of multiviewer functionality
- Uses official Matrox Convert IP REST API endpoints

#### Device Identification
- Supports flexible device lookup by serial number, device name, or alias
- Handles multiple serial number formats (e.g., "YXA00634", "8700634", "CIP-DEC-634")
- Robust error handling for device discovery and API calls

#### Debug Output
- Multiviewer toggle events generate debug logs when `DEBUG_ENABLED = true`
- Device status changes are logged for troubleshooting
- API response status is tracked and reported

### Supported Commands

- **Connect**: `join <encoder> <decoder>`
- **Disconnect**: `stop <decoder>`
- **Multi-connection**: Support for multiple encoder/decoder pairs
- **Multiviewer Toggle**: Per-decoder multiviewer enable/disable

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
3. **WebSocket Port**: Ensure port 8080 (or configured port) is accessible
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
