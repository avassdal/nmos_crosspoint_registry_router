--[[ 
  NMOS Crosspoint Router Control for Q-Sys (WebSocket API)
  
  Description:
  This script provides a direct interface to control an NMOS Crosspoint Router via its WebSocket API.
  It uses the native Q-Sys WebSocket and rapidjson modules.

  WebSocket API Commands Used:
  - POST /makeconnection

  Q-Sys Setup:
  1. Add this script to a "Control Script" component in Q-Sys Designer.
  2. Create the following controls in the script's parent component:
     - `Controls["IP Address"]` (Type: String) - Set this to the IP of the crosspoint router.
]]--

-- Required modules
rapidjson = require("rapidjson")

-- IMPORTANT: Router credentials (defined globally for access throughout the script)
ROUTER_USER = "admin"
ROUTER_PASSWORD = "password"

-- Runtime Variables -- (all defined at global scope to prevent garbage collection)
receive_buffer = ""
pingTimer = nil 
reconnectTimer = nil
authTimeoutTimer = nil
isConnecting = false
isAuthenticated = false
isSocketConnected = false

function New_ProcessMessage(json_string)
  print("DEBUG: Processing message: " .. json_string)
  -- Use pcall to safely decode JSON and catch any errors
  local ok, response = pcall(rapidjson.decode, json_string)

  if not ok then
    print("ERROR: Failed to decode JSON from server: " .. tostring(response))
    -- Log the problematic string for troubleshooting, but limit output to avoid console spam
    local preview = json_string
    if #json_string > 100 then preview = json_string:sub(1, 100) .. "..." end
    print("ERROR: Problematic JSON: '" .. preview .. "'")
    return
  end
  
  -- For debug visibility, when needed
  -- local pretty_json = rapidjson.encode(response, {pretty=true, sort_keys=true})
  -- print("DEBUG: Decoded JSON object: " .. pretty_json)
  
  print("DEBUG: Processing message of type: " .. response.type)
  
  if response.type == "auth" and response.user then
    -- This is likely an echo or acknowledgment of our auth request
    -- We can safely ignore it as we're waiting for authok
    print("DEBUG: Received auth echo for user '" .. response.user .. "'. Waiting for auth confirmation...")
    
    -- After receiving echo, proactively check for authentication issues
    if response.error then
      print("ERROR: Authentication error: " .. tostring(response.error))
      if reconnectTimer then reconnectTimer:Stop() end
      Controls["Connection status"].String = "Auth Error: " .. tostring(response.error)
    end
    
  elseif response.type == "authseed" then
    print("DEBUG: Authentication seed received: " .. response.seed)
    
    -- Generate auth response using SHA256(PASSWORD + SEED)
    local password_hash_status, password_hash_or_err = pcall(Crypto.Digest, 'sha256', ROUTER_PASSWORD)
    if not password_hash_status then
      print("FATAL: Could not hash password. Error: " .. tostring(password_hash_or_err))
      if reconnectTimer then reconnectTimer:Stop() end
      Controls["Connection status"].String = "Crypto Error"
      return
    end
    
    print("DEBUG: First hash successful")
    local password_hex_hash = toHex(password_hash_or_err)
    local password_seed = password_hex_hash .. response.seed
    print("DEBUG: Combined hash with seed: " .. #password_seed .. " bytes")
    
    local status, hash_or_err = pcall(Crypto.Digest, 'sha256', password_seed)
    if not status then
      print("FATAL: Crypto.Digest failed. Error: " .. tostring(hash_or_err))
      if reconnectTimer then reconnectTimer:Stop() end
      Controls["Connection status"].String = "Crypto Error"
      return
    end
    
    local hex_hash = toHex(hash_or_err)
    print("DEBUG: Generated final auth hash from password and seed")
    
    local json_command = string.format('{"type":"auth","user":"%s","password":"%s"}', ROUTER_USER, hex_hash)
    print("DEBUG: Sending authentication response: " .. json_command)
    ws:Write(json_command)
    
    -- Set up a timer to proceed with subscriptions if no explicit authok is received
    -- Some servers might not send an explicit authok response
    print("DEBUG: Setting up authentication timeout to proceed with subscriptions in 3 seconds")
    -- Create a timeout timer in case we don't receive explicit 'authok'
    if authTimeoutTimer then authTimeoutTimer:Stop() end
    
    -- Initialize or reuse the global timer
    if not authTimeoutTimer then
      authTimeoutTimer = Timer.New()
      authTimeoutTimer.EventHandler = function(timer)
        print("DEBUG: Auth timeout reached - proceeding with subscription")
        authTimeoutTimer:Stop()
        if not isAuthenticated then
          print("DEBUG: No explicit authok received, assuming success and proceeding")
          isAuthenticated = true
          -- Proceed with subscriptions
          Controls["Connection status"].String = "Connected and Authenticated"
          SubscribeToData("mediadevices")
          Timer.CallAfter(function() SubscribeToData("mediadevmatroxcip") end, 1)
        end
      end
    end
    
    authTimeoutTimer:Start(3) -- 3 second timeout
    
  elseif response.type == "authok" then
    print("DEBUG: Authentication successful!")
    isAuthenticated = true
    
    -- Update UI
    Component.Status = "OK"
    Controls["Connection status"].String = "Connected & Authenticated"
    
    -- Subscribe to mediadevices
    print("DEBUG: Subscribing to 'mediadevices'...")
    SubscribeToData("mediadevices")
    
    -- Schedule second subscription with a delay
    print("DEBUG: Scheduling 'mediadevmatroxcip' subscription in 1 second")
    Timer.CallAfter(DoSecondSubscription, 1)
    
  elseif response.type == "sync" then
    print("DEBUG: Received sync message for channel: " .. (response.channel or "<unknown>") .. ", objectId: " .. (response.objectId or "<unknown>"))
    
    -- Check if this is a subscription confirmation or data update
    if not response.channel then
      print("ERROR: Received sync message with no channel")
      return
    end
    
    if response.channel == "mediadevices" then
      print("DEBUG: Received mediadevices sync data")
      -- If this is the first sync message for mediadevices, it means the subscription was successful
      if response.first then
        print("DEBUG: Successfully subscribed to mediadevices channel")
      end
    elseif response.channel == "mediadevmatroxcip" then
      print("DEBUG: Processing Matrox CIP data")
      if response.first then
        print("DEBUG: Successfully subscribed to mediadevmatroxcip channel")
      end
      
      -- Process the data if it exists
      if response.data then
        print("DEBUG: Updating CIP status with received data")
        UpdateCipStatus(response.data)
      else
        print("DEBUG: No data in sync message for mediadevmatroxcip")
      end
    else
      print("DEBUG: Received sync message for unhandled channel: " .. (response.channel or "<unknown>"))
    end

  elseif response.type == "authfailed" or response.type == "autherror" then
    print("ERROR: Authentication failed: " .. (response.error or "Unknown reason"))
    Component.Status = "Error"
    Controls["Connection status"].String = "Auth Failed: " .. (response.error or "Unknown error")
    
    -- Stop reconnection attempts
    if reconnectTimer then reconnectTimer:Stop() end

  elseif response.type == "response" then
    print("DEBUG: Response to request ID " .. tostring(response.id) .. ": " .. response.message)

  elseif response.type == "permissionDenied" then
    print("ERROR: Permission denied for '" .. tostring(response.data and response.data.name) .. "'. Reason: " .. tostring(response.data and response.data.reason))
    Component.Status = "Fault"
    Controls["Connection status"].String = "Permission Denied"
    
  elseif response.type == "ping" or response.type == "pong" then
    print("DEBUG: Received " .. response.type .. " message")
    

  else
    -- Dump the full message for unexpected types to aid debugging
    print("Received unhandled message type: '" .. response.type .. "'")
    local pretty_json = rapidjson.encode(response, {pretty=true, sort_keys=true})
    print("DEBUG: Full message contents: " .. pretty_json)
    
    -- Try to continue processing even with unknown message types
    -- Some servers may use non-standard message types
    if not isAuthenticated and response.user == ROUTER_USER then
      print("DEBUG: Server responded to authentication but didn't send explicit authok")
      print("DEBUG: Assuming authentication successful based on received message")
      isAuthenticated = true
      Component.Status = "OK"
      Controls["Connection status"].String = "Connected & Authenticated"
      
      -- Subscribe to mediadevices
      print("DEBUG: Subscribing to 'mediadevices'...")
      SubscribeToData("mediadevices")
      
      -- Schedule second subscription with a delay
      print("DEBUG: Scheduling 'mediadevmatroxcip' subscription in 1 second")
      Timer.CallAfter(DoSecondSubscription, 1)
    end
  end
end

function New_OnDataReceived(w, data)
  if not data or data == "" then return end
  
  print("DEBUG: Adding data to buffer (" .. #data .. " bytes)")
  receive_buffer = receive_buffer .. data
  
  print("DEBUG: Buffer now contains " .. #receive_buffer .. " bytes")
  
  -- Look for newline characters to find complete messages
  local pos = 1
  local found_complete_message = false
  
  while true do
    local start_pos, end_pos = receive_buffer:find("\n", pos)
    if not start_pos then
      print("DEBUG: No more complete messages in buffer")
      break -- No more complete lines
    end

    local line = receive_buffer:sub(pos, start_pos - 1)
    if line and line ~= "" then
      print("DEBUG: Found complete message: " .. #line .. " bytes")
      found_complete_message = true
      New_ProcessMessage(line)
    else
      print("DEBUG: Found empty line, skipping")
    end

    pos = end_pos + 1
  end

  -- Trim the processed part from the buffer
  if pos > 1 then
    receive_buffer = receive_buffer:sub(pos)
    print("DEBUG: Buffer trimmed, now contains " .. #receive_buffer .. " bytes")
  end
  
  if not found_complete_message then
    print("DEBUG: No complete messages found, waiting for more data")
    -- If no newline was found, try processing what we have if it looks like a complete JSON object
    if receive_buffer:match("^%s*{.+}%s*$") then
      print("DEBUG: Buffer contains what looks like a complete JSON object, processing it anyway")
      New_ProcessMessage(receive_buffer)
      receive_buffer = ""
    end
  end
end

-- End of message handling logic

-- *********************
-- *   Dependencies    *
-- *********************
-- rapidjson already loaded globally at the top of the script

-- *********************
-- *   Configuration   *
-- *********************

local ROUTER_PORT = 80 -- WebSocket port
local RECONNECT_INTERVAL = 5 -- seconds
local EncoderNames = {
  "CIP-ENC-659", "CIP-ENC-630", "CIP-ENC-604", "CIP-ENC-668",
  "CIP-ENC-619", "CIP-ENC-616", "CIP-ENC-637", "CIP-ENC-601",
  "CIP-ENC-646", "CIP-ENC-660", "CIP-ENC-664", "CIP-ENC-686"
}
local DISCONNECT_CHOICE = "-- DISCONNECT --"

-- Router credentials are defined globally at the top of the script
-- DO NOT redefine them here

-- *********************
-- *   Global Vars     *
-- *********************

ws = nil -- Global WebSocket object
-- Global variables are already defined at top of script
local format = string.format
local request_id = 1



-- *********************
-- *   Functions       *
-- *********************

-- Helper function to convert a raw string to a hex-encoded string
function toHex(str)
  if type(str) ~= "string" then return "" end
  return (str:gsub('.', function (c)
    return string.format('%02x', string.byte(c))
  end))
end


-- Helper to subscribe to a sync object
function SubscribeToData(objectName)
  if ws and isSocketConnected and isAuthenticated then
    -- The server expects 'type: "sync"', the object name in 'channel', and the default data under objectId 0.
    local subscribe_msg = {
      type = "sync",
      channel = objectName,
      objectId = 0
    }
    
    local json_command = rapidjson.encode(subscribe_msg)
    print("DEBUG: Sending subscribe request for '" .. objectName .. "': " .. json_command)
    ws:Write(json_command)
  else
    print("WARNING: Cannot subscribe to '" .. objectName .. "' - not connected or not authenticated")
    print("DEBUG: Socket connected: " .. tostring(isSocketConnected) .. ", Authenticated: " .. tostring(isAuthenticated))
  end
end

-- Function to be called after a delay to perform the second subscription
function DoSecondSubscription()
  print("Subscribing to 'mediadevmatroxcip'...")
  SubscribeToData("mediadevmatroxcip")
end

-- Helper function to determine a device's status from its state object
function GetDeviceStatus(device)
  if device.unreachable then return "Unreachable" end
  if device.failed then return "Failed: " .. (device.error or "Unknown") end
  if device.sessionConflict then return "Session Conflict" end
  if device.loading then return "Loading..." end
  return "OK"
end

-- Processes mediadevmatroxcip data and updates the CIP-Status control
function UpdateCipStatus(data)
  if not Controls["CIP-Status"] then return end

  -- Log the raw data for debugging
  local raw_json_data, json_err = rapidjson.encode(data)
  if raw_json_data then
    print("UpdateCipStatus received data: " .. raw_json_data)
  else
    print("UpdateCipStatus: Failed to encode received data for logging.")
  end

  local output_devices = {}
  if data and data.devices then
    -- data.devices is a dictionary (table with string keys), so we use pairs()
    for sn, device in pairs(data.devices) do
      table.insert(output_devices, {
        name = device.name or "N/A",
        sn = device.sn or sn, -- Use key as fallback for SN
        ip = table.concat(device.ipList or {}, ", "),
        firmware = device.firmwareVersion or "N/A",
        status = GetDeviceStatus(device)
      })
    end
  end

  local output_table = { devices = output_devices }
  local json_output, err = rapidjson.encode(output_table)
  
  if json_output then
    Controls["CIP-Status"].String = json_output
  else
    local error_msg = "Error encoding CIP status to JSON: " .. (err or "unknown error")
    print(error_msg)
    Controls["CIP-Status"].String = '{"error": "' .. error_msg .. '"}'
  end
end

function ConnectToServer()
  local ip = Controls["IP Address"].String
  if not isConnecting and ip ~= "" and ROUTER_PORT > 0 then
    isConnecting = true
    Controls["Connection status"].String = "Connecting..."
    print("Attempting to connect to ws://" .. ip .. ":" .. ROUTER_PORT .. "/")

    -- Create a new WebSocket client
    ws = WebSocket.New()
    
    -- Ensure ping timer is properly set up (only create if it doesn't exist)
    if not pingTimer then
      print("DEBUG: Creating new ping timer")
      pingTimer = Timer.New() -- Use the global variable
      
      -- Define the event handler directly with the timer
      -- This ensures the timer isn't garbage collected
      pingTimer.EventHandler = function(timer)
        print("DEBUG: Sending ping to keep connection alive")
        if ws then
          ws:Ping()
          print("DEBUG: Ping sent successfully")
        else
          print("WARNING: Cannot send ping, ws object is nil")
        end
      end
    else
      print("DEBUG: Using existing ping timer")
      pingTimer:Stop() -- Ensure it's stopped before connecting
    end
    isSocketConnected = false -- Reset on new connection attempt

    -- WebSocket event handlers are defined below


    print("DEBUG: Setting up WebSocket event handlers...")
    
    -- Connected event handler
    print("DEBUG: Registering ws.Connected callback...")
    ws.Connected = function()
      print("DEBUG: ws.Connected event fired. WebSocket is now CONNECTED.")
      -- Update connection state
      isSocketConnected = true
      Component.Status = "OK"
      Controls["Connection status"].String = "Connected, authenticating..."
      
      -- Stop reconnect timer if it was running
      if reconnectTimer then reconnectTimer:Stop() end
      
      -- Start the ping timer (every 30 seconds)
      print("DEBUG: Starting ping timer to keep connection alive")
      if pingTimer then pingTimer:Start(30) end
      
      print("DEBUG: Should now start receiving data if server sends any...")
      -- Send a dummy message to potentially trigger the server to respond
      print("DEBUG: Sending a dummy ping message to server...")
      ws:Write("{\"type\":\"ping\"}")
    end
    
    -- Closed event handler
    print("DEBUG: Registering ws.Closed callback...")
    ws.Closed = function()
      print("DEBUG: ws.Closed event fired. WebSocket connection CLOSED.")
      
      -- Update connection state
      isSocketConnected = false
      isAuthenticated = false
      Component.Status = "Compromised"
      Controls["Connection status"].String = "Disconnected. Reconnecting..."
      
      -- Stop ping timer
      print("DEBUG: Stopping ping timer")
      if pingTimer then pingTimer:Stop() end
      
      -- Start reconnect timer
      print("DEBUG: Attempting reconnect in " .. RECONNECT_INTERVAL .. " seconds...")
      if reconnectTimer then 
        reconnectTimer:Stop() 
        reconnectTimer:Start(RECONNECT_INTERVAL)
      end
    end
    
    -- Data event handler
    print("DEBUG: Registering custom data handler function...")
    ws.Data = function(w, data)
      print("DEBUG: ws.Data event fired! Received data of type: " .. type(data))
      if type(data) == "string" then
        print("DEBUG: Data is a string. Length: " .. #data .. ".")
        -- Print first 50 chars max to avoid log pollution
        local preview = data
        if #data > 50 then preview = data:sub(1, 50) .. "..." end
        print("DEBUG: Data preview: '" .. preview .. "'")
      else
        print("DEBUG: Data is of unexpected type: " .. type(data))
      end
      
      -- Call our proper handler
      New_OnDataReceived(w, data)
    end
    
    -- Error event handler
    print("DEBUG: Registering ws.Error callback...")
    ws.Error = function(w, err)
      print("DEBUG: WebSocket ERROR: " .. tostring(err))
      
      -- Update connection state
      isSocketConnected = false
      Component.Status = "Fault"
      Controls["Connection status"].String = "WebSocket Error: " .. tostring(err)
      
      -- Stop ping timer
      if pingTimer then pingTimer:Stop() end
      
      -- Try to reconnect after error
      if reconnectTimer then 
        reconnectTimer:Stop()
        reconnectTimer:Start(RECONNECT_INTERVAL)
      end
    end
    
    -- Pong event handler
    print("DEBUG: Adding ws.Pong callback...")
    ws.Pong = function()
      print("DEBUG: Received pong response from server")
    end

    print("DEBUG: About to call ws:Connect('ws', '" .. ip .. "', '/', " .. ROUTER_PORT .. ")")
    -- Connect using the "ws" protocol. Use "wss" for secure connections.
    ws:Connect("ws", ip, "/", ROUTER_PORT)
    print("DEBUG: Connect called. Connection attempt in progress...")
  else
    Component.Status = "Fault"
    Controls["Connection status"].String = "Idle - No IP Address"
    print("Connection failed: IP Address control is empty.")
  end
end

function SendCommand(payload)
  if ws and isSocketConnected and isAuthenticated then
    local command = {
      type = "request",
      method = "POST",
      route = "makeconnection",
      id = tostring(request_id),
      data = payload
    }
    request_id = request_id + 1

    local json_command, err = rapidjson.encode(command)
    if json_command then
      print("Sending command: " .. json_command)
      ws:Write(json_command)
    else
      print(format("Failed to encode JSON command: %s", err))
    end
  else
    print("Command not sent. Not connected.")
    Controls["Connection status"].String = "Error: Not Connected"
    Component.Status = "Fault"
  end
end

function OnDecoderSourceChanged(sourceControl, decoderControl)
  -- Defensive check: Q-Sys may fire the handler at startup with invalid arguments.
  -- We only proceed if we get valid control objects (tables).
  -- Defensive check: Q-Sys may fire the handler with invalid arguments (e.g., a 'string' on init).
  -- We only proceed if we get valid control objects, which can be 'table' or 'userdata'.
  if (type(sourceControl) ~= "table" and type(sourceControl) ~= "userdata") or (type(decoderControl) ~= "table" and type(decoderControl) ~= "userdata") then
    return
  end

  local sourceName = sourceControl.String
  local decoderName = decoderControl.String

  print(format("Routing change for Decoder '%s' -> Source '%s'", tostring(decoderName), tostring(sourceName)))

  if decoderName and decoderName ~= "" then
    local payload
    if sourceName == DISCONNECT_CHOICE then
      -- To disconnect, we send a null source for the given destination.
      payload = {
        destination = decoderName,
        source = rapidjson.null
      }
    else
      -- To connect, we send the source and destination.
      payload = {
        source = sourceName,
        destination = decoderName
      }
    end
    SendCommand(payload)
  else
    print(format("WARNING: Decoder control (original index %d) is empty. Cannot send command.", decoderControl.Index))
  end
end

-- *************************
-- * Initialization Logic  *
-- *************************

function Initialize()
  print("Initializing Crosspoint Router Script (WebSocket API)...")

  if not Controls["CIP-Status"] then
    print("WARNING: Control 'CIP-Status' not found. Matrox CIP status will not be displayed.")
  end

  if not Controls["Connection status"] then 
    print("FATAL: Control 'Connection status' not found.")
    Component.Status = "Fault"
    return 
  end

  Component.Status = "Initializing"
  Controls["Connection status"].String = "Initializing Script..."

  if not Controls["IP Address"] then 
    print("FATAL: Control 'IP Address' not found.")
    Component.Status = "Fault"
    Controls["Connection status"].String = "FATAL: Control 'IP Address' not found."
    return 
  end

  -- Setup reconnect timer once during initialization
  if not reconnectTimer then
    reconnectTimer = Timer.New()
    reconnectTimer.EventHandler = function()
      ConnectToServer()
    end
    print("DEBUG: Created reconnect timer")
  end

  -- Set up event handler for the IP Address control.
  Controls["IP Address"].EventHandler = function()
    if ws then ws:Close() end
    if reconnectTimer then reconnectTimer:Stop() end
    ConnectToServer()
  end

  -- Add handler for preset JSON input
  -- Add handler for preset JSON input
  if Controls.Code and type(Controls.Code) == "table" then
    Controls.Code.EventHandler = function(control)
      -- Defensively check if the argument is the control object (a table) or just its initial value (a string)
      if type(control) ~= "table" then
        return
      end

      local json_string = control.String
      if json_string == nil or json_string == "" then
        return -- Ignore empty input
      end

      print("Received new JSON preset. Processing...")
      local ok, payload = pcall(rapidjson.decode, json_string)

      if not ok then
        print(format("ERROR: Invalid JSON in preset control: %s", tostring(payload)))
        return
      end

      SendCommand(payload)
    end
    print("Initialized JSON preset handler for 'Controls.Code'.")
  end

  -- Create the list of choices for the source dropdowns
  local sourceChoices = { DISCONNECT_CHOICE }
  for _, encoderName in ipairs(EncoderNames) do
    table.insert(sourceChoices, encoderName)
  end
  
  -- To handle sparse tables from Q-Sys, we will collect all controls and sort them
  local sortedDecoderSources = {}
  if Controls.DecoderSource and type(Controls.DecoderSource) == "table" then
    for _, control in pairs(Controls.DecoderSource) do
      table.insert(sortedDecoderSources, control)
    end
    table.sort(sortedDecoderSources, function(a, b) return a.Index < b.Index end)
  end

  local sortedDecoders = {}
  if Controls.Decoder and type(Controls.Decoder) == "table" then
    for _, control in pairs(Controls.Decoder) do
      table.insert(sortedDecoders, control)
    end
    table.sort(sortedDecoders, function(a, b) return a.Index < b.Index end)
  end

  if #sortedDecoderSources == 0 then
    print("WARNING: 'Controls.DecoderSource' not found or is empty.")
  else
    if #sortedDecoderSources ~= #sortedDecoders then
      print(format("WARNING: Mismatch in control counts. Found %d 'DecoderSource' controls and %d 'Decoder' controls. Only the first %d will be mapped.", #sortedDecoderSources, #sortedDecoders, math.min(#sortedDecoderSources, #sortedDecoders)))
    end

    -- Register event handlers using the new sorted tables
    for i = 1, math.min(#sortedDecoderSources, #sortedDecoders) do
      local sourceControl = sortedDecoderSources[i]
      local decoderControl = sortedDecoders[i]

      sourceControl.Choices = sourceChoices

      -- The event handler function closes over the correct source and decoder controls
      sourceControl.EventHandler = function(ctrl)
        OnDecoderSourceChanged(ctrl, decoderControl)
      end
    end
    print(format("Initialized %d decoder source controls.", #sortedDecoderSources))
  end

  -- Attempt the initial connection on script start
  ConnectToServer()
  
  print("Initialization complete.")
end

Initialize()
