
# KubeVirt Guacamole Auto-Connect Operator
This Kubernetes Operator dynamically provisions Apache Guacamole connections for newly created VMs managed by KubeVirt. It seamlessly integrates with Keycloak (via OpenID) to provide a secure, automated remote access experience with zero manual configuration.

---

## Key Features

- **Automatic Guacamole Connection Creation**  
  When a VM is created in KubeVirt, the operator sends a POST request to Apache Guacamole’s management API to create a connection automatically.

- **Integrated Authentication via Keycloak**  
  Users are redirected to Keycloak for authentication using OpenID Connect. No Guacamole credentials are needed.

- **Zero Touch User Experience**  
  Users who log in to Guacamole via Keycloak are immediately presented with their VM connections — no manual setup or UI interaction is required.

---

## Components

* **KubeVirt:** Manages VM lifecycle on Kubernetes.
* **Kubebuilder Operator:** Watches for new `VirtualMachineInstance` objects and triggers connection creation.
* **Apache Guacamole:** Provides browser-based remote desktop access (VNC, RDP, SSH).
* **Keycloak:** Handles user authentication via OpenID Connect.

---

## Prerequisites

* Kubernetes cluster with:

  * [KubeVirt](https://kubevirt.io/)
  * [Apache Guacamole](https://guacamole.apache.org/) (with REST API access enabled)
  * [Keycloak](https://www.keycloak.org/)
* Guacamole configured to use Keycloak as its OpenID provider.
* Proper RoleBindings and RBAC permissions for the operator.

---

## How It Works

1. The operator listens for `VirtualMachineInstance` (`VMI`) creation events via the Kubernetes API.

2. When a new VM is detected:
   * VM metadata (IP, name, etc.) is extracted.
   * A REST API call is made to Guacamole to create a new connection with appropriate parameters.

3. When the user accesses the Guacamole UI:
   * They are redirected to Keycloak for authentication.
   * Upon successful login, they are presented with the dynamically created connection(s) for their VM(s).

---

## Deployment

1. Build and deploy the operator:

2. Ensure the operator has access to `VirtualMachineInstances`.

3. Configure environment variables or a ConfigMap for:

   * Guacamole API URL and credentials
   * Keycloak OpenID endpoints (if needed)
   * Any connection defaults (protocol, port, etc.)

---

## Security Considerations

* Only users authenticated via Keycloak can access the dashboard.
* Operator does not expose or persist credentials outside the Guacamole/Keycloak scope.
* All connection creation happens within the cluster boundary via trusted API calls.

---

## Contribution

Pull requests are welcome! If you'd like to contribute.

## License

MIT License
