import { NetworkAuth, NetworkInfrastructure, NetworkInterface, AttachedNetworkDevice } from "./networkDevice";
import { NetworkInfrastructureConnector } from "./networkInfrastructureConnector";
import { Agent } from 'undici';

// Helper function to safely get nested properties
const get = (obj: any, path: string, defaultValue: any = undefined) => {
    const properties = path.split('.');
    return properties.reduce((acc, prop) => (acc && typeof acc === 'object' && prop in acc) ? acc[prop] : defaultValue, obj);
};

export class NIC_MOD extends NetworkInfrastructureConnector {
    device: NetworkInfrastructure;
    private updateIntervalTimer: NodeJS.Timeout | null = null;
    private apiBaseUrl: string;
    private apiToken: string | null = null;
    private authOptions: NetworkAuth;
    private httpsAgent: Agent;

    constructor(auth: NetworkAuth, changedCallback: any) {
        super(auth, changedCallback);

        this.authOptions = auth;
        // Create an undici Agent that allows self-signed certificates
        this.httpsAgent = new Agent({
            connect: {
                rejectUnauthorized: false
            }
        });

        this.device = {
            id: auth.name, // Unique ID, can be hostname or serial
            name: auth.name,
            model: "",
            serialNumber: "",
            version: "",
            interfaces: [],
            rendering: { mode: "m4350" }, // For UI rendering hints
            source: "config",
            type: "switch",
        };

        if (!auth.connect) {
            console.error(`M4350 (${auth.name}): Connection IP/hostname not provided.`);
            // Potentially throw an error or disable the connector
            this.apiBaseUrl = '';
            return;
        }
        this.apiBaseUrl = `https://${auth.connect}:8443/api/v1`;

        console.log(`M4350 connector initialized for: ${auth.name} at ${this.apiBaseUrl}`);

        this.fetchAndUpdateDeviceData().then(() => {
            super.update(this.device);
            this.startPolling();
        }).catch(error => {
            console.error(`M4350 (${this.device.name}): Initial data fetch failed:`, error);
            // Still start polling, it might recover
            this.startPolling();
        });
    }

    private async login(): Promise<boolean> {
        if (!this.authOptions.user || !this.authOptions.password) {
            console.error(`M4350 (${this.device.name}): API credentials (user/password) not provided.`);
            return false;
        }

        const loginUrl = `${this.apiBaseUrl}/login`;
        const credentials = {
            login: {
                username: this.authOptions.user,
                password: this.authOptions.password,
            },
        };

        let responseText = ''; // Variable to store raw response text
        try {
            const response = await fetch(loginUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(credentials),
                dispatcher: this.httpsAgent // Use dispatcher with undici.Agent
            });

            responseText = await response.text(); // Get response as text first

            if (!response.ok) {
                console.error(`M4350 (${this.device.name}): Login HTTP error! Status: ${response.status}`);
                console.error(`M4350 (${this.device.name}): Response body: ${responseText}`);
                // Optionally try to parse if it might sometimes be JSON, though likely not for errors
                try {
                    const errorData = JSON.parse(responseText);
                    console.error(`M4350 (${this.device.name}): Parsed error details:`, errorData);
                } catch (e) {
                    // It's fine if parsing error response fails, raw text is already logged
                }
                return false;
            }

            // Try to parse the successful response text as JSON
            try {
                const data = JSON.parse(responseText);
                if (data && data.token) {
                    this.apiToken = data.token;
                    console.log(`M4350 (${this.device.name}): Login successful. Token received.`);
                    return true;
                } else {
                    console.error(`M4350 (${this.device.name}): Login succeeded but no token in response. Data:`, data);
                    console.error(`M4350 (${this.device.name}): Raw response body: ${responseText}`);
                    return false;
                }
            } catch (jsonParseError) {
                console.error(`M4350 (${this.device.name}): Error parsing successful login response as JSON.`);
                console.error(`M4350 (${this.device.name}): Raw response body: ${responseText}`);
                console.error(jsonParseError); // Log the parsing error itself
                return false;
            }

        } catch (fetchError: any) { // Catch any error during fetch or response.text()
            console.error(`M4350 (${this.device.name}): Error during login request or reading response:`, fetchError.message);
            if (responseText) { // If we managed to get responseText before another error
                console.error(`M4350 (${this.device.name}): Raw response body (if available): ${responseText}`);
            }
            return false;
        }
    }

    private async fetchWithAuth(url: string, options: RequestInit = {}): Promise<Response | null> {
        if (!this.apiToken) {
            console.log(`M4350 (${this.device.name}): No API token. Attempting to login first.`);
            const loggedIn = await this.login();
            if (!loggedIn || !this.apiToken) {
                console.error(`M4350 (${this.device.name}): Cannot fetch data, login required or failed.`);
                return null;
            }
        }

        const headers = {
            ...options.headers,
            'Authorization': `Bearer ${this.apiToken}`,
            'Content-Type': 'application/json' // Usually good to have for GETs too, though not always necessary
        };

        try {
            const response = await fetch(url, { 
                ...options, 
                headers, 
                dispatcher: this.httpsAgent // Use dispatcher with undici.Agent
            });
            if (response.status === 401 || response.status === 403) { // Unauthorized or Forbidden
                console.warn(`M4350 (${this.device.name}): Auth error (${response.status}). Token might be invalid/expired. Re-logging in...`);
                this.apiToken = null; // Clear token
                const loggedIn = await this.login();
                if (loggedIn && this.apiToken) {
                    headers['Authorization'] = `Bearer ${this.apiToken}`;
                    console.log(`M4350 (${this.device.name}): Re-login successful. Retrying request to ${url}`);
                    return fetch(url, { 
                        ...options, 
                        headers, 
                        dispatcher: this.httpsAgent // Use dispatcher for retry as well
                    }); // Retry the request with new token
                }
                console.error(`M4350 (${this.device.name}): Re-login failed. Cannot retry request.`);
                return response; // Return original error response
            }
            return response;
        } catch (error) {
            console.error(`M4350 (${this.device.name}): Error during fetch to ${url}:`, error);
            throw error; // Re-throw to be caught by the caller
        }
    }

    private async fetchDeviceInfo(): Promise<void> {
        const url = `${this.apiBaseUrl}/device_info`;
        const response = await this.fetchWithAuth(url, { method: 'GET' });

        if (response && response.ok) {
            const data = await response.json();
            // Accessing nested properties correctly based on observed data structure
            this.device.model = get(data, 'deviceInfo.model', '');
            this.device.serialNumber = get(data, 'deviceInfo.serialNumber', '');
            this.device.version = get(data, 'deviceInfo.swVer', ''); // swVer for software version

            if (this.device.model && this.device.serialNumber && this.device.version) {
                console.log(`M4350 (${this.device.name}): Fetched device info - Model: ${this.device.model}, SN: ${this.device.serialNumber}, Ver: ${this.device.version}`);
            } else {
                console.warn(`M4350 (${this.device.name}): Partially fetched device info. Some fields might be missing. Raw data:`, JSON.stringify(data, null, 2));
            }
        } else if (response) {
            console.error(`M4350 (${this.device.name}): Failed to fetch device info - ${response.status} ${response.statusText}`);
        } else {
            // fetchWithAuth returned null (e.g. login failure)
            // Error already logged by fetchWithAuth or login
        }
    }

    private async fetchInterfaceStatus(): Promise<void> {
        const url = `${this.apiBaseUrl}/sw_portstats?portid=ALL`;
        const response = await this.fetchWithAuth(url, { method: 'GET' });
        const newInterfaces: NetworkInterface[] = [];

        if (response && response.ok) {
            const data = await response.json();
            console.log(`M4350 (${this.device.name}): Raw data from /sw_portstats BEFORE get:`, JSON.stringify(data, null, 2));
            const portStatsList = get(data, 'portStats', []); 
            console.log(`M4350 (${this.device.name}): portStatsList AFTER get:`, JSON.stringify(portStatsList, null, 2));
            console.log(`M4350 (${this.device.name}): typeof portStatsList: ${typeof portStatsList}, isArray: ${Array.isArray(portStatsList)}, length: ${portStatsList && Array.isArray(portStatsList) ? portStatsList.length : 'N/A or not an array'}`);

            if (!portStatsList || !Array.isArray(portStatsList) || portStatsList.length === 0) {
                console.warn(`M4350 (${this.device.name}): portStatsList is not a populated array. Path: 'portStats'. Raw data and portStatsList content logged above.`);
            }

            for (const ifaceData of portStatsList) {
                const portId = String(ifaceData.portId);
                // Determine link state: assuming status 1 is link up and adminMode is true
                const linkUp = ifaceData.adminMode === true && ifaceData.status === 1;

                let attachedDevice: AttachedNetworkDevice | null = null;
                if (ifaceData.neighborInfo && ifaceData.neighborInfo.chassisId) {
                    attachedDevice = {
                        chassisId: String(ifaceData.neighborInfo.chassisId),
                        portId: String(ifaceData.neighborInfo.portId || ''),
                        name: String(ifaceData.neighborInfo.name || '') // This is the neighbor's system name
                    };
                }
                
                newInterfaces.push({
                    id: portId,
                    name: ifaceData.myDesc || `Port ${portId}`,
                    mac: ifaceData.portMacAddress || '',
                    // Speed and MaxSpeed: Using raw value. Further mapping/interpretation might be needed.
                    // M4350 API docs list speed as an enum: 1 (10M), 2 (100M), 3 (1G), 4 (2.5G), 5 (5G), 6 (10G), 7 (25G), 8 (40G), 9 (50G), 10 (100G), 11 (Max Speed of Port)
                    // For now, we'll just store the numeric value. 'Max Speed of Port' (11) is ambiguous without knowing the port's actual max speed.
                    speed: typeof ifaceData.speed === 'number' ? ifaceData.speed : 0, 
                    maxspeed: typeof ifaceData.speed === 'number' ? ifaceData.speed : 0, // Placeholder, ideally, map enum or get specific max_speed if available
                    num: parseInt(portId.replace(/[^0-9]/g, '')) || ifaceData.portId, // Use direct portId if non-numeric
                    type: 'unknown', // Type (RJ45, SFP) is not directly available in this endpoint
                    linkState: linkUp ? 'up' : 'down',
                    // Duplex: Enum (e.g., 65535). Using 'unknown' until mapping is clear.
                    duplex: String(ifaceData.duplex) || 'unknown', // Store raw enum or 'unknown'
                    attached: attachedDevice,
                });
            }
            this.device.interfaces = newInterfaces;
            console.log(`M4350 (${this.device.name}): Updated ${newInterfaces.length} interfaces from /sw_portstats.`);
        } else if (response) {
            console.error(`M4350 (${this.device.name}): Failed to fetch interface status - ${response.status} ${response.statusText}`);
        }
    }

    private async fetchLldpInfo(): Promise<void> {
        const url = `${this.apiBaseUrl}/lldp_remote_devices`;
        const response = await this.fetchWithAuth(url, { method: 'GET' });

        if (response && response.ok) {
            const data = await response.json();
            // Assuming structure like: { lldp_remote_devices: { lldp_rem_dev_list: [...] } }
            // Or directly: { lldp_rem_dev_list: [...] }
            // This path is a GUESS based on the endpoint name '/lldp_remote_devices'
            const lldpList = get(data, 'lldp_remote_devices.lldp_rem_dev_list') || get(data, 'lldp_rem_dev_list') || [];

            if (!lldpList || lldpList.length === 0) {
                console.warn(`M4350 (${this.device.name}): No LLDP data found in /lldp_remote_devices response or response was empty. Raw data:`, JSON.stringify(data, null, 2));
            }

            let updatedCount = 0;
            for (const lldpData of lldpList) {
                // Field names below are GUESSES. Adjust to actual API response.
                const localPortId = String(lldpData.local_port_id || lldpData.localPortId || lldpData.local_interface || '');
                const existingInterface = this.device.interfaces.find(iface => iface.id === localPortId);

                if (existingInterface) {
                    existingInterface.attached = {
                        chassisId: lldpData.remote_chassis_id || lldpData.chassisId || '',
                        portId: lldpData.remote_port_id || lldpData.portId || '',
                        name: lldpData.remote_system_name || lldpData.systemName || '', // System Name of the neighbor
                        // Add other fields if available and needed by AttachedNetworkDevice
                    };
                    updatedCount++;
                }
            }
            if (updatedCount > 0) {
                console.log(`M4350 (${this.device.name}): Updated LLDP info for ${updatedCount} interfaces.`);
            }
        } else if (response) {
            console.error(`M4350 (${this.device.name}): Failed to fetch LLDP info - ${response.status} ${response.statusText}`);
        }
    }

    private async fetchAndUpdateDeviceData(): Promise<void> {
        console.log(`M4350 (${this.device.name}): Starting data fetch cycle.`);
        if (!this.apiBaseUrl) {
            console.warn(`M4350 (${this.device.name}): API base URL not set. Skipping fetch.`);
            return;
        }

        try {
            // Ensure we are logged in, or login if no token exists
            if (!this.apiToken) {
                const loggedIn = await this.login();
                if (!loggedIn) {
                    console.error(`M4350 (${this.device.name}): Login failed. Aborting data fetch cycle.`);
                    // Optionally, schedule a retry for login later or stop polling if login is critical.
                    return; 
                }
            }
            
            // Fetch data in parallel or sequence. Parallel is faster if endpoints are independent.
            await Promise.all([
                this.fetchDeviceInfo(),
                this.fetchInterfaceStatus() // Fetch interfaces first, then LLDP can attach to them
            ]);

            // Fetch LLDP info after interfaces are populated
            if (this.device.interfaces.length > 0) {
                await this.fetchLldpInfo();
            }

            console.log(`M4350 (${this.device.name}): Data fetch cycle completed.`);
            super.update(this.device); // Notify the base class of changes

        } catch (error) {
            console.error(`M4350 (${this.device.name}): Error during data fetch cycle:`, error);
            // Decide on error handling: e.g., clear device data, retry, stop polling
            // For now, we'll let polling continue, hoping it's a transient issue.
        }
    }

    private startPolling(intervalMilliseconds: number = 30000): void {
        if (this.updateIntervalTimer) {
            clearInterval(this.updateIntervalTimer);
        }
        // Ensure polling doesn't start if base URL isn't set (constructor failed)
        if (!this.apiBaseUrl) {
            console.warn(`M4350 (${this.device.name}): API base URL not configured. Polling will not start.`);
            return;
        }
        this.updateIntervalTimer = setInterval(async () => {
            await this.fetchAndUpdateDeviceData();
        }, intervalMilliseconds);
        console.log(`M4350 (${this.device.name}): Polling started every ${intervalMilliseconds / 1000}s`);
    }

    public stopPolling(): void {
        if (this.updateIntervalTimer) {
            clearInterval(this.updateIntervalTimer);
            this.updateIntervalTimer = null;
            console.log(`M4350 (${this.device.name}): Polling stopped`);
        }
    }

    public cleanup(): void {
        this.stopPolling();
        this.apiToken = null; // Clear token on cleanup
        console.log(`M4350 (${this.device.name}): Cleaned up connector.`);
    }
}
