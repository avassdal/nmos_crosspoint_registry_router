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
- WebSocket access enabled on NMOS Router

## Installation

1. **Add Script to Q-SYS Designer**:
   - Open your Q-SYS design file
   - Add a "Control Script" component
   - Copy and paste the contents of `q-sys-crosspoint-control.lua`

2. **Create Required Controls**:
   - `Controls["IP Address"]` (String): IP address of NMOS Crosspoint Router
   - `Controls["Connection status"]` (String): Connection status display
   - `Controls["CIP-Status"]` (String): Matrox CIP status (optional)
   - `Controls["Device State"]` (String): Current device state display

3. **Create Decoder Controls**:
   - `Controls.Decoder` (Array of String): Decoder device names
   - `Controls.DecoderSource` (Array of Knob/Combo): Source selection for each decoder

## Configuration

### Basic Settings

```lua
-- Router credentials (modify as needed)
ROUTER_USER = "admin"
ROUTER_PASSWORD = "password"

-- Debug and monitoring flags
DEBUG_ENABLED = false      -- Set true for verbose logging
ENABLE_PATCH_STATS = false -- Set true for patch statistics
```

### Network Configuration

1. Set the IP address in `Controls["IP Address"]` to your NMOS Router server
2. Ensure proper network routing between Q-SYS Core and NMOS Router
3. Configure firewall rules to allow WebSocket connections (typically port 8080)

## Usage

### Connection Process

1. **Initial Connection**: The script automatically attempts to connect when loaded
2. **Authentication**: Uses SHA256 password hashing with server-provided seed
3. **Device Discovery**: Automatically discovers available NMOS devices
4. **Subscription**: Subscribes to real-time updates for device state changes

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

### Supported Commands

- **Connect**: `join <encoder> <decoder>`
- **Disconnect**: `stop <decoder>`
- **Multi-connection**: Support for multiple encoder/decoder pairs

## API Integration

### WebSocket Messages

The script handles several message types from the NMOS Router:

- **auth**: Authentication challenge
- **authseed**: Authentication seed for password hashing
- **authok**: Successful authentication
- **sync**: Real-time state synchronization
- **patch**: Incremental updates to device state

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
- **"Authentication failed"**: Verify credentials and user permissions
- **"Connection timeout"**: Check firewall and network routing

### Device Discovery Issues

1. **No devices found**: Ensure NMOS devices are properly registered
2. **Missing devices**: Check NMOS registry configuration
3. **Stale device list**: Restart the script or wait for automatic refresh

## Advanced Configuration

### Custom Device Mapping

The script supports custom device naming and mapping:

```lua
-- Example custom encoder/decoder mapping
EncoderNames = {"Studio_Encoder", "Remote_Encoder", "Backup_Encoder"}
DecoderNames = {"Main_Decoder", "Preview_Decoder", "Record_Decoder"}
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
- Configure appropriate ping intervals to balance responsiveness with network load

### Memory Management
- The script automatically manages device data storage
- Large device lists may impact Q-SYS Core performance
- Consider limiting scope if experiencing performance issues

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
