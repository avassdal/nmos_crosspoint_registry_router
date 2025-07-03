# WebSocket API Documentation

This document outlines the WebSocket API for the NMOS Crosspoint Router. The API is divided into two main parts: **Synchronized Objects** for real-time state management and **API Routes** for performing actions.

## 1. Overview

The API uses a custom WebSocket protocol built on top of the `ws` library. Clients can subscribe to `SyncObject`s to receive real-time updates and can send messages to invoke `API Routes` to trigger server-side actions.

- **Connection**: Clients connect to the WebSocket server at the address and port specified in `config/settings.json`.
- **Authentication**: If `config/users.json` is configured, clients may need to authenticate.

## 2. Synchronized Objects

Synchronized Objects provide a real-time view of the server's state. Clients can subscribe to these objects by name and will receive the full object state upon subscription, followed by patches for any subsequent changes.

| Object Name           | Permissions | Description                                                                                                                               |
| --------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `log`                 | `global`    | A real-time stream of server-side logs.                                                                                                   |
| `nmos`                | `global`    | A complete, real-time representation of all discovered NMOS resources, including nodes, devices, senders, receivers, and flows.             |
| `nmosConnectionState` | `global`    | The connection status of the server to the various NMOS registries it has discovered.                                                     |
| `crosspoint`          | `global`    | The core crosspoint model, representing a simplified, user-friendly view of all devices and their available senders and receivers.        |
| `mediadevices`        | `global`    | A list of all dynamically loaded media devices (e.g., Matrox, Riedel) and their current states.                                           |
| `uiconfig`            | `public`    | General UI configuration, primarily used to inform the client about which server-side modules have been disabled.                         |

## 3. API Routes

API Routes are used to perform specific actions on the server. They are invoked by sending a JSON message over the WebSocket connection.

### `GET /flowInfo`

Retrieves detailed information about a specific NMOS flow, including its manifest.

- **Method**: `GET`
- **Permissions**: `global`
- **Query Parameters**:
  - `query[0]` (string): The ID of the flow to query (e.g., `"nmos_..."`).

### `POST /makeconnection`

Creates, prepares, or previews a connection between one or more senders and receivers.

- **Method**: `POST`
- **Permissions**: `global`
- **Payload**:

```json
{
  "source": "<sender_id>",
  "destination": "<receiver_id>",
  "preview": false, // Optional: if true, returns a preview without executing
  "prepare": false  // Optional: if true, prepares the connection
}
```

*or for multiple connections:*

```json
{
  "multiple": [
    { "source": "<sender_id_1>", "destination": "<receiver_id_1>" },
    { "source": "<sender_id_2>", "destination": "<receiver_id_2>" }
  ]
}
```

### `POST /changealias`

Changes the user-defined alias for a device or flow.

- **Method**: `POST`
- **Permissions**: `global`
- **Payload**:

```json
{
  "id": "<device_or_flow_id>",
  "alias": "New Alias Name"
}
```

### `POST /enableFlow`

Activates a specific NMOS flow.

- **Method**: `POST`
- **Permissions**: `global`
- **Payload**:

```json
{
  "id": "<nmos_flow_id>"
}
```

### `POST /disableFlow`

Deactivates a specific NMOS flow.

- **Method**: `POST`
- **Permissions**: `global`
- **Payload**:

```json
{
  "id": "<nmos_flow_id>"
}
```

### `POST /setMulticast`

Sets the multicast address for an NMOS flow.

- **Method**: `POST`
- **Permissions**: `global`
- **Payload**:

```json
{
  "id": "<nmos_flow_id>",
  "data": { ... } // The multicast configuration data
}
```

### `POST /togglehidden`

Toggles the visibility of a device or flow in the UI.

- **Method**: `POST`
- **Permissions**: `global`
- **Payload**:

```json
{
  "id": "<device_or_flow_id>"
}
```

### `POST /crosspoint`

A general-purpose endpoint for the crosspoint editor UI to send more complex API commands.

- **Method**: `POST`
- **Permissions**: `global`
- **Payload**: A flexible object structure defined by the needs of the crosspoint editor.
