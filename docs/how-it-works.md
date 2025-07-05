## Component Interactions

### 1. VM Creation to Connection Flow

```mermaid
sequenceDiagram
    participant K8s as Kubernetes
    participant Op as Operator
    participant VM as VirtualMachine
    participant G as Guacamole
    participant DB as PostgreSQL

    K8s->>Op: VM Created Event
    Op->>VM: Check VM Status
    VM->>Op: Status: Running
    Op->>G: Authenticate
    G->>Op: Auth Token
    Op->>G: Create Connection
    G->>DB: Store Connection
    Op->>VM: Add Connection ID Annotation
```

### 2. User Access Flow

```mermaid
sequenceDiagram
    participant U as User
    participant KC as Keycloak
    participant G as Guacamole
    participant VM as VM

    U->>G: Access Guacamole
    G->>KC: Redirect for Auth
    KC->>U: Login Form
    U->>KC: Credentials
    KC->>G: Auth Token
    G->>U: Show Available Connections
    U->>G: Select Connection
    G->>VM: Establish Remote Session
```

## VM Lifecycle Management

The operator manages the complete lifecycle of VM connections:

### 1. Creation Phase

When a new VM is created or updated:

1. **Event Detection**: The operator receives a Kubernetes event for VM creation/update
2. **Status Check**: Verifies the VM is running and has an IP address
3. **Connection Configuration**: Builds Guacamole connection parameters:
   - **Protocol**: VNC (default) or RDP
   - **Hostname**: VM IP address or service name
   - **Port**: 5900 (VNC) or 3389 (RDP)
   - **Authentication**: Configurable via VM annotations

### 2. Configuration Details

The operator extracts VM connection details from multiple sources:

```go
// Connection parameters are built from:
connection := GuacamoleConnection{
    Name:     vm.Name + " (Auto-created)",
    Protocol: "vnc", // or "rdp"
    Parameters: map[string]string{
        "hostname": vmIP,
        "port":     "5900",
        "password": "", // Can be set via annotations
    },
}
```

### 3. Update Phase

When VM configuration changes:

1. **Change Detection**: Operator detects VM generation or status changes
2. **Connection Update**: Updates existing Guacamole connection if parameters changed
3. **Annotation Sync**: Maintains connection ID in VM annotations

### 4. Deletion Phase

When a VM is deleted:

1. **Finalizer Check**: Operator processes deletion via Kubernetes finalizers
2. **Connection Cleanup**: Removes corresponding Guacamole connection
3. **Database Cleanup**: Connection data is removed from PostgreSQL

## Dynamic Connection Creation Process

The operator automatically creates personalized Guacamole connections for each VM using a sophisticated detection and configuration system. Here's how the dynamic creation works:

### 1. VM Event Detection and Processing

The operator uses Kubernetes controller patterns to watch for VM lifecycle events:

```go
// The controller processes three types of events:
// 1. CREATE: New VM is detected
// 2. UPDATE: VM status or configuration changes
// 3. DELETE: VM is being removed
```

#### Event Flow for New VMs:

1. **Event Trigger**: Kubernetes notifies the operator when a new VM is created
2. **Finalizer Addition**: The operator adds a finalizer to ensure proper cleanup
3. **Status Validation**: Waits for VM to reach "Running" state
4. **Connection Creation**: Builds and creates Guacamole connection
5. **Annotation Storage**: Stores connection metadata in VM annotations

### 2. Connection Configuration Building

The operator dynamically builds connection configurations based on VM properties and annotations:

#### Protocol Detection:

```bash
# Default protocol is RDP, but can be customized via annotations:
kubectl annotate vm my-vm vm-watcher.setofangdar.polito.it/protocol=vnc
kubectl annotate vm my-vm vm-watcher.setofangdar.polito.it/port=5900
```

#### Supported Protocols:

- **RDP** (default): Port 3389, Windows VMs
- **VNC**: Port 5900, Linux VMs, general purpose
- **SSH**: Port 22, terminal access

#### Dynamic Hostname Resolution:

1. **VMI IP Extraction**: Gets actual VM IP from VirtualMachineInstance status
2. **Service Discovery**: Looks for Kubernetes services exposing the VM
3. **Fallback**: Uses VM name as hostname

### 3. Connection Parameter Generation

The operator automatically configures protocol-specific parameters:

#### RDP Configuration:

```json
{
  "hostname": "vm-ip-address",
  "port": "3389",
  "security": "any",
  "ignore-cert": "true",
  "resize-method": "reconnect",
  "console-audio": "false",
  "enable-wallpaper": "false"
}
```

#### VNC Configuration:

```json
{
  "hostname": "vm-ip-address",
  "port": "5900",
  "color-depth": "24",
  "cursor": "remote",
  "read-only": "false",
  "disable-copy": "false",
  "enable-audio": "false"
}
```

### 4. Annotation-Based Customization

Users can customize connection behavior through VM annotations:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: custom-vm
  annotations:
    # Protocol settings
    vm-watcher.setofangdar.polito.it/protocol: "vnc"
    vm-watcher.setofangdar.polito.it/port: "5901"

    # Authentication (if needed)
    vm-watcher.setofangdar.polito.it/username: "admin"
    vm-watcher.setofangdar.polito.it/password: "secret"
    vm-watcher.setofangdar.polito.it/domain: "COMPANY"
```

### 5. Connection Lifecycle Management

The operator maintains connection state throughout the VM lifecycle:

#### State Tracking via Annotations:

```yaml
metadata:
  annotations:
    # Processing state
    vm-watcher.setofangdar.polito.it/processed: "true"
    vm-watcher.setofangdar.polito.it/last-status: "Running"

    # Connection reference
    vm-watcher.setofangdar.polito.it/guacamole-connection-id: "12345"
```

#### Status-Based Actions:

- **VM Running**: Create/update connection with current IP
- **VM Stopped**: Connection remains but may be disabled
- **VM Restarted**: Update connection with new IP if changed
- **VM Deleted**: Remove connection from Guacamole

### 6. Authentication and API Integration

The operator authenticates with Guacamole using admin credentials and REST API:

```go
// Authentication flow:
// 1. POST /api/tokens with admin credentials
// 2. Receive auth token for subsequent requests
// 3. Use token for connection CRUD operations

authURL := fmt.Sprintf("%s/api/tokens", guacamoleBaseURL)
createURL := fmt.Sprintf("%s/api/session/data/%s/connections?token=%s",
    guacamoleBaseURL, dataSource, authToken)
```

## Guacamole REST API Endpoints

The operator interacts with Guacamole through its REST API using four main endpoints. Here's a detailed breakdown of each endpoint, the data sent, and their functionality:

### 1. Authentication Endpoint

**Endpoint**: `POST /api/tokens`

**Purpose**: Authenticate with Guacamole and obtain an auth token for subsequent API calls.

**Request Format**:

```http
POST /api/tokens
Content-Type: application/x-www-form-urlencoded

username=guacadmin&password=guacadmin
```

**Request Data**:

```go
data := url.Values{}
data.Set("username", r.GuacamoleUsername) // Admin username
data.Set("password", r.GuacamolePassword) // Admin password
```

**Response Format**:

```json
{
  "authToken": "8F1D2E4F6A7B8C9D0E1F2A3B4C5D6E7F",
  "username": "guacadmin",
  "dataSource": "postgresql",
  "availableDataSources": ["postgresql"]
}
```

**Response Struct**:

```go
type GuacamoleAuthResponse struct {
    AuthToken            string   `json:"authToken"`
    Username             string   `json:"username"`
    DataSource           string   `json:"dataSource"`
    AvailableDataSources []string `json:"availableDataSources"`
}
```

**Functionality**:

- Validates admin credentials against the Guacamole database
- Returns an authentication token valid for the session
- Provides data source information (typically "postgresql")
- Token is used in all subsequent API calls as a query parameter

### 2. Connection Creation Endpoint

**Endpoint**: `POST /api/session/data/{dataSource}/connections?token={authToken}`

**Purpose**: Create a new remote desktop connection configuration in Guacamole.

**Request Format**:

```http
POST /api/session/data/postgresql/connections?token=8F1D2E4F6A7B8C9D0E1F2A3B4C5D6E7F
Content-Type: application/json

{
  "parentIdentifier": "ROOT",
  "name": "development-dev-workstation",
  "protocol": "rdp",
  "parameters": {
    "hostname": "10.244.0.15",
    "port": "3389",
    "security": "any",
    "ignore-cert": "true",
    "username": "developer",
    "password": "secret"
  },
  "attributes": {
    "max-connections": "",
    "max-connections-per-user": "",
    "weight": ""
  }
}
```

**Request Data Structure**:

```go
type GuacamoleConnection struct {
    ParentIdentifier string            `json:"parentIdentifier"` // "ROOT" for top-level
    Name             string            `json:"name"`             // "namespace-vmname"
    Protocol         string            `json:"protocol"`         // "rdp", "vnc", "ssh"
    Parameters       map[string]string `json:"parameters"`       // Protocol-specific config
    Attributes       map[string]string `json:"attributes"`       // Connection limits, etc.
}
```

**Parameters by Protocol**:

**RDP Parameters**:

```json
{
  "hostname": "vm-ip-address",
  "port": "3389",
  "security": "any",
  "ignore-cert": "true",
  "resize-method": "reconnect",
  "console-audio": "false",
  "enable-wallpaper": "false",
  "username": "user",
  "password": "pass",
  "domain": "COMPANY"
}
```

**VNC Parameters**:

```json
{
  "hostname": "vm-ip-address",
  "port": "5900",
  "color-depth": "24",
  "cursor": "remote",
  "read-only": "false",
  "disable-copy": "false",
  "enable-audio": "false",
  "password": "vnc-password"
}
```

**SSH Parameters**:

```json
{
  "hostname": "vm-ip-address",
  "port": "22",
  "font-size": "12",
  "username": "user",
  "password": "pass",
  "private-key": "-----BEGIN RSA PRIVATE KEY-----..."
}
```

**Response Format**:

```json
{
  "identifier": "12345",
  "parentIdentifier": "ROOT",
  "name": "development-dev-workstation",
  "protocol": "rdp",
  "parameters": {
    "hostname": "10.244.0.15",
    "port": "3389"
  },
  "attributes": {}
}
```

**Response Struct**:

```go
type GuacamoleConnectionResponse struct {
    Identifier       string            `json:"identifier"`       // Generated connection ID
    ParentIdentifier string            `json:"parentIdentifier"`
    Name             string            `json:"name"`
    Protocol         string            `json:"protocol"`
    Parameters       map[string]string `json:"parameters"`
    Attributes       map[string]string `json:"attributes"`
}
```

**Functionality**:

- Creates a new connection entry in the Guacamole database
- Generates a unique connection identifier (UUID)
- Stores all connection parameters and attributes
- Initially accessible only to the admin user who created it
- Returns the connection ID for future reference

### 3. Connection Update Endpoint

**Endpoint**: `PUT /api/session/data/{dataSource}/connections/{connectionId}?token={authToken}`

**Purpose**: Update an existing connection configuration (e.g., when VM IP changes).

**Request Format**:

```http
PUT /api/session/data/postgresql/connections/12345?token=8F1D2E4F6A7B8C9D0E1F2A3B4C5D6E7F
Content-Type: application/json

{
  "parentIdentifier": "ROOT",
  "name": "development-dev-workstation",
  "protocol": "rdp",
  "parameters": {
    "hostname": "10.244.0.25",  // Updated IP
    "port": "3389",
    "security": "any",
    "ignore-cert": "true"
  },
  "attributes": {}
}
```

**Request Data**: Same structure as creation, but with updated parameters

**Response**: HTTP 204 No Content (success) or error status

**Functionality**:

- Updates existing connection parameters in the database
- Commonly used when VM restarts with a new IP address
- Preserves connection sharing/permissions settings
- Does not affect existing user sessions

### 4. Connection Deletion Endpoint

**Endpoint**: `DELETE /api/session/data/{dataSource}/connections/{connectionId}?token={authToken}`

**Purpose**: Remove a connection configuration when VM is deleted.

**Request Format**:

```http
DELETE /api/session/data/postgresql/connections/12345?token=8F1D2E4F6A7B8C9D0E1F2A3B4C5D6E7F
```

**Request Data**: No body, connection ID in URL path

**Response**: HTTP 204 No Content (success) or error status

**Functionality**:

- Completely removes connection from Guacamole database
- Cascades to remove all associated permissions and settings
- Terminates any active sessions using this connection
- Cannot be undone - connection must be recreated if needed

### API Authentication Flow

```mermaid
sequenceDiagram
    participant Op as Operator
    participant G as Guacamole API
    participant DB as PostgreSQL

    Op->>G: POST /api/tokens (username, password)
    G->>DB: Validate credentials
    DB->>G: User verified
    G->>Op: AuthToken + DataSource

    Op->>G: POST /connections?token=... (connection config)
    G->>DB: INSERT connection
    DB->>G: Connection ID
    G->>Op: Connection response

    Op->>G: PUT /connections/{id}?token=... (updated config)
    G->>DB: UPDATE connection
    G->>Op: Success

    Op->>G: DELETE /connections/{id}?token=...
    G->>DB: DELETE connection
    G->>Op: Success
```

### Error Handling

All endpoints return HTTP status codes and JSON error responses:

**Common Error Responses**:

```json
// Authentication failure
{
  "message": "Permission denied.",
  "statusCode": 401
}

// Invalid connection data
{
  "message": "Invalid connection configuration.",
  "statusCode": 400
}

// Connection not found
{
  "message": "No such connection.",
  "statusCode": 404
}
```

**Status Code Handling in Operator**:

```go
if resp.StatusCode != http.StatusOK {
    return fmt.Errorf("authentication failed with status %d", resp.StatusCode)
}

if resp.StatusCode < 200 || resp.StatusCode >= 300 {
    return fmt.Errorf("operation failed with status %d", resp.StatusCode)
}
```

### Database Impact

Each API call corresponds to database operations:

```sql
-- Authentication: Query user table
SELECT user_id, password_hash FROM guacamole_user WHERE username = ?;

-- Create Connection: Insert into multiple tables
INSERT INTO guacamole_connection (connection_name, protocol) VALUES (?, ?);
INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES (?, ?, ?);

-- Update Connection: Update existing records
UPDATE guacamole_connection_parameter SET parameter_value = ? WHERE connection_id = ? AND parameter_name = ?;

-- Delete Connection: Cascade delete
DELETE FROM guacamole_connection WHERE connection_id = ?;
-- Triggers cascade delete of parameters, permissions, etc.
```

### Future API Enhancements

### 7. Error Handling and Retries

The operator implements robust error handling:

- **Retry Logic**: Failed operations retry with exponential backoff
- **State Reconciliation**: Periodic checks ensure consistency
- **Graceful Degradation**: System continues working if some VMs fail

### 8. Current User Access Model

**Important**: Currently, all auto-created connections are **only accessible by the Guacamole admin user** who created them.

#### Current Access Flow:

1. **Admin-Only Creation**: Operator creates connection using admin credentials
2. **Default Permissions**: Connection inherits admin user's ownership
3. **Manual Sharing Required**: Admin must manually share with users/groups via Guacamole UI
4. **No Automation**: No automatic assignment based on VM properties

### Example Dynamic Creation Workflow

```bash
# 1. Create VM with custom annotations
kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: dev-workstation
  namespace: development
  annotations:
    vm-watcher.setofangdar.polito.it/protocol: "rdp"
    vm-watcher.setofangdar.polito.it/username: "developer"
    # Future: vm-watcher.setofangdar.polito.it/auto-share-groups: "dev-team:READ"
spec:
  running: true
  template:
    # VM template...
EOF

# 2. Monitor operator processing
kubectl logs -n kubebuilderproject-system deployment/kubebuilderproject-controller-manager -f

# 3. Check connection creation
kubectl get vm dev-workstation -o jsonpath='{.metadata.annotations}'

# Output shows:
# {
#   "vm-watcher.setofangdar.polito.it/processed": "true",
#   "vm-watcher.setofangdar.polito.it/last-status": "Running",
#   "vm-watcher.setofangdar.polito.it/guacamole-connection-id": "abc-123-def"
# }

# 4. Connection appears in Guacamole as: "development-dev-workstation"
```

## Current Connection Sharing Workflow

**⚠️ Important Limitation**: Connection sharing with users and groups is currently a **manual process** that requires administrative action in the Guacamole UI after each VM connection is created.

### Manual Sharing Process Required

#### 1. Automatic Connection Creation

When a VM is created and becomes running:

```bash
# VM is created
kubectl apply -f vm-definition.yaml

# Operator automatically creates Guacamole connection
# Connection appears in Guacamole as: "vm-name (Auto-created)"
# BUT: Only accessible by the admin user who created it
```

#### 2. Manual Sharing Steps (Required)

After the connection is automatically created, an administrator must manually:

1. **Login to Guacamole** as admin user
2. **Navigate to Settings** → Connections
3. **Select the auto-created connection**
4. **Click "Permissions" tab**
5. **Manually add users or groups** with appropriate permissions (READ, UPDATE, DELETE, ADMINISTER)

### Current Limitations

1. **Manual Process**: Sharing must be done manually for each connection
2. **No Automation**: No automatic user/group assignment based on VM properties
3. **Admin Dependency**: Requires administrator intervention for each new VM
4. **Scale Issues**: Becomes burdensome with many VMs and users
5. **No Group-based Automation**: Cannot automatically share with groups based on VM annotations

### Example Current Workflow

```bash
# 1. Create VM
kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: dev-vm-001
  namespace: default
spec:
  # VM configuration...
EOF

# 2. Wait for VM to be running
kubectl wait --for=condition=Ready vm/dev-vm-001 --timeout=300s

# 3. Operator automatically creates Guacamole connection
# Connection ID is stored in VM annotation:
kubectl get vm dev-vm-001 -o jsonpath='{.metadata.annotations.vm-watcher\.setofangdar\.polito\.it/guacamole-connection-id}'

# 4. MANUAL STEP: Admin must now share connection in Guacamole UI
# - Login to Guacamole as admin
# - Navigate to Settings → Connections
# - Find "dev-vm-001 (Auto-created)" connection
# - Click Edit → Permissions tab
# - Add users or groups with appropriate permissions (READ, UPDATE, DELETE, ADMINISTER)
# - Save changes
```

## Data Flow

### Database Schema

PostgreSQL stores data for both Guacamole and Keycloak:

```sql
-- Guacamole tables
guacamole_connection       -- Connection definitions
guacamole_connection_permission -- User/group permissions
guacamole_user            -- User accounts

-- Keycloak tables
user_entity               -- User accounts
keycloak_group           -- Group definitions
user_group_membership    -- User-group relationships
```

### Connection Storage

When the operator creates a connection:

```sql
-- Connection is stored with:
INSERT INTO guacamole_connection (
    connection_name,
    protocol,
    connection_id
) VALUES (
    'vm-name (Auto-created)',
    'vnc',
    'generated-uuid'
);

-- Parameters are stored separately:
INSERT INTO guacamole_connection_parameter (
    connection_id,
    parameter_name,
    parameter_value
) VALUES
    (connection_id, 'hostname', 'vm-ip-address'),
    (connection_id, 'port', '5900');
```

## Controller Logic

### Reconciliation Loop

The operator controller follows the standard Kubernetes reconciliation pattern:

```go
func (r *VirtualMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. Fetch VM from Kubernetes
    vm := &kubevirtv1.VirtualMachine{}
    err := r.Get(ctx, req.NamespacedName, vm)

    // 2. Handle deletion
    if vm.DeletionTimestamp != nil {
        return r.handleVMDeletion(ctx, vm)
    }

    // 3. Add finalizer for cleanup
    if !controllerutil.ContainsFinalizer(vm, VMWatcherFinalizer) {
        controllerutil.AddFinalizer(vm, VMWatcherFinalizer)
        return ctrl.Result{}, r.Update(ctx, vm)
    }

    // 4. Check if VM is running
    if vm.Status.PrintableStatus != kubevirtv1.VirtualMachineStatusRunning {
        return ctrl.Result{RequeueAfter: DefaultRetryDelay}, nil
    }

    // 5. Create or update Guacamole connection
    return r.ensureGuacamoleConnection(ctx, vm)
}
```

### Event Filtering

The controller only processes relevant events:

```go
vmPredicate := predicate.Funcs{
    CreateFunc: func(e event.CreateEvent) bool {
        return true // Process all create events
    },
    UpdateFunc: func(e event.UpdateEvent) bool {
        oldVM := e.ObjectOld.(*kubevirtv1.VirtualMachine)
        newVM := e.ObjectNew.(*kubevirtv1.VirtualMachine)

        // Only process if status or generation changed
        return oldVM.Status.PrintableStatus != newVM.Status.PrintableStatus ||
               oldVM.Generation != newVM.Generation
    },
    DeleteFunc: func(e event.DeleteEvent) bool {
        return true // Process all delete events
    },
}
```

### Error Handling and Retries

The controller implements robust error handling:

1. **Retry Logic**: Failed operations are retried with exponential backoff
2. **Status Tracking**: VM annotations track processing state
3. **Cleanup Guarantees**: Finalizers ensure proper cleanup even if operator restarts

### Future Enhancements

The current manual sharing workflow will be enhanced with automatic group-based sharing. See [automatic-group-sharing-enhancement.md](automatic-group-sharing-enhancement.md) for the planned implementation.

Key improvements will include:

1. **Annotation-Driven Sharing**: VM annotations specify target groups
2. **Automatic Permission Assignment**: Connections automatically shared with groups
3. **Role-Based Access**: Different permission levels based on group roles
4. **Reduced Manual Work**: Eliminate manual sharing steps for administrators

---

_This document describes the current state of the system. For troubleshooting information, see [troubleshoot.md](troubleshoot.md)._
