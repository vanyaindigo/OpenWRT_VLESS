### Script Description

This script automates the configuration of OpenWrt routers to enable advanced routing, DNS resolution, and traffic management. It is designed to support selective routing (split tunneling) for specific domains or services while ensuring secure and efficient network operation. Below is a detailed description of what the script does:

---

### **Key Features**
1. **Selective Routing (Split Tunneling):**
   - Routes traffic for specific domains (e.g., internal/domestic domains) through a designated interface (`wan`) using `ru_table`.
   - Routes all other traffic through a VPN tunnel (`tun0`) using `vpn_table`.

2. **DNS Configuration:**
   - Installs and configures `dnsmasq-full` for advanced DNS handling.
   - Sets up DNS over TLS using `Stubby` to protect DNS queries from spoofing.
   - Dynamically resolves domain names into IP addresses and updates `ipset` rules for selective routing.

3. **Traffic Marking and Firewall Rules:**
   - Marks traffic for specific domains (e.g., internal/domestic domains) with `mark 0x1` and routes it through `ru_table`.
   - Marks all other traffic with `mark 0x2` and routes it through `vpn_table`.
   - Configures firewall zones and forwarding rules for proper traffic segregation.

4. **Sing-Box Integration:**
   - Installs and configures Sing-Box (a modern proxy tool) for tunneling traffic.
   - Creates a `tun0` interface and sets up routing rules for the tunnel.
   - Provides a template configuration file (`/etc/sing-box/config.json`) that can be customized for your needs.

5. **Automated Domain Updates:**
   - Creates a cron job to periodically resolve domain names into IP addresses and update the `ipset` rules.
   - Ensures that changes in domain IP addresses are automatically reflected in the routing rules.

6. **System Compatibility:**
   - Works only with OpenWrt versions 23.05 and 24.10.
   - Checks for available disk space before installing large packages like Sing-Box.

---

### **How It Works**
1. **Initial Setup:**
   - Checks the availability of the OpenWrt repository and updates the package list.
   - Verifies the router's model and OpenWrt version compatibility.

2. **Routing Table Configuration:**
   - Creates two routing tables: `ru_table` (for internal/domestic domains) and `vpn_table` (for all other traffic).
   - Adds rules to route traffic based on marks (`0x1` for `ru_table` and `0x2` for `vpn_table`).

3. **Firewall and IPSet Rules:**
   - Creates an `ipset` for internal/domestic domains (e.g., `yandex.ru`, `mail.ru`, `vk.com`).
   - Adds firewall rules to mark traffic for these domains and route them through `ru_table`.

4. **DNS Resolution:**
   - Configures `dnsmasq-full` to use `Stubby` for DNS over TLS.
   - Periodically resolves domain names into IP addresses and updates the `ipset` rules.

5. **Sing-Box Integration:**
   - Installs Sing-Box if sufficient disk space is available.
   - Configures the `tun0` interface and sets up routing rules for the tunnel.

6. **Cron Job for Automation:**
   - Sets up a cron job to run every 8 hours to update domain IP addresses and ensure accurate routing.

7. **Final Steps:**
   - Restarts the network and related services to apply the changes.

---

### **Usage Instructions**
1. **Prerequisites:**
   - Ensure your router is running OpenWrt 23.05 or 24.10.
   - Make sure you have sufficient disk space (at least 2MB for basic functionality, 20MB+ for Sing-Box).

2. **Run the Script:**
   - Copy the script to your router and execute it:
     ```bash
     sh <(wget -O - https://raw.githubusercontent.com/vanyaindigo/OpenWRT_VLESS/refs/heads/main/sinbox-install.sh)
     ```


3. **Customize Configuration:**
   - Edit `/etc/sing-box/config.json` to configure Sing-Box for your proxy server.
   - Modify the list of internal/domestic domains in `/etc/init.d/getdomains` if needed.

4. **Verify Functionality:**
   - Check routing tables and firewall rules:
     ```bash
     ip rule show
     ip route show table ru_table
     ip route show table vpn_table
     ```
   - Test DNS resolution and ensure traffic is routed correctly.

---

### **Limitations**
- The script assumes basic familiarity with OpenWrt and command-line operations.
- Some features (e.g., Sing-Box configuration) require manual configuration of keys and endpoints.
- Disk space constraints may prevent the installation of certain packages (e.g., Sing-Box).

---

### **Contributing**
If you encounter issues or have suggestions for improvement, feel free to open an issue or submit a pull request. Contributions are welcome!

---

### **License**
This script is released under the MIT License.
---

### **Acknowledgments**
- Thanks to the OpenWrt community for providing robust tools and documentation.
- Special thanks to contributors of `dnsmasq`, `Stubby`, and `Sing-Box` for their excellent software.
