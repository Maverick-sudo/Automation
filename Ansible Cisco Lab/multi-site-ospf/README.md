# Multi-Site OSPF Lab with Phased Deployment

## Lab Topology Overview

This lab demonstrates a realistic multi-site OSPF deployment across two campus networks connected via ABR (Area Border Router) routers.

### Network Segments

- **PNet0 (192.168.33.0/24)**: Management network (NAT - Internet access)
- **PNet1 (172.16.47.0/24)**: Site A / Area 0 Campus (Host-only with DHCP)
- **PNet2 (10.200.200.0/24)**: Site B / Area 1 Campus (Host-only without DHCP)

### Router Roles

| Router | Role | Management Network | Data Network | OSPF Role |
|--------|------|-------------------|--------------|-----------|
| R4 | Area 0 Core | 172.16.47.204 (PNet0) | PNet1 | Internal |
| R5 | ABR-0 | xxx.xxx.xxx.xxx (PNet1) | PNet1 + ABR Link | ABR |
| R6 | Area 0 Edge | 172.16.47.206 (PNet0) | PNet1 | Internal |
| R7 | Area 1 Core | 10.200.200.207 (PNet0) | PNet2 | Internal |
| R8 | ABR-1 | xxx.xxx.xxx.xxx (PNet2) | PNet2 + ABR Link | ABR |
| R9 | Area 1 Edge | 10.200.200.209 (PNet0) | PNet2 | Internal |

### Addressing Scheme

**Management Plane:**
- PNet0: 192.168.33.0/24 (R4, R6, R7, R9)
- PNet1: 172.16.47.0/24 (R5 only)
- PNet2: 10.200.200.0/24 (R8 only)

**Data Plane:**
- Area 0 internal: 10.10.20.0/30, 10.10.20.4/30
- Area 1 internal: 10.10.10.0/30, 10.10.10.4/30
- ABR link: 203.0.113.0/30
- Loopbacks: X.X.X.X/32 (router ID)
- Simulated LANs: 172.16.47.0/24 (Area 0), 10.200.200.0/24 (Area 1)

---

## Prerequisites

### Linux Ansible Control Node Setup

**CRITICAL:** The Ansible control node must have routes to reach PNet1 and PNet2 networks.
```bash
# Add route to PNet1 (Area 0 Campus)
sudo ip route add 172.16.47.0/24 via 192.168.33.130

# Add route to PNet2 (Area 1 Campus)
sudo ip route add 10.200.200.0/24 via 192.168.33.130

# Verify routes
ip route show | grep -E "172.16.47|10.200.200"

# Make persistent (add to /etc/netplan/ or /etc/network/interfaces)
**Note:** Replace `192.168.33.130` with your EVE-NG host IP if different.

**Make routes persistent:**

For Ubuntu/Debian with netplan:
```bash
sudo nano /etc/netplan/99-eve-routes.yaml
```

Add:
```yaml
network:
  version: 2
  routes:
    - to: 172.16.47.0/24
      via: 192.168.33.130
    - to: 10.200.200.0/24
      via: 192.168.33.130
```

Apply:
```bash
sudo netplan apply
```

### EVE-NG Internal Routing Setup

Ensure EVE-NG host has IP forwarding enabled and routes between pnet interfaces.

On EVE-NG host:
```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Make persistent
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Add iptables rules for forwarding
sudo iptables -A FORWARD -i pnet0 -o pnet1 -j ACCEPT
sudo iptables -A FORWARD -i pnet1 -o pnet0 -j ACCEPT
sudo iptables -A FORWARD -i pnet0 -o pnet2 -j ACCEPT
sudo iptables -A FORWARD -i pnet2 -o pnet0 -j ACCEPT

# Save rules
sudo netfilter-persistent save


---

## Deployment Process

This lab uses a **two-phase deployment** strategy to handle the bootstrap problem where ABR routers (R5, R8) are not directly reachable from the Ansible control node.

### Phase 1: Deploy Core Campus Routers

Deploy OSPF on routers directly reachable from Ansible (R4, R6, R7, R9). This establishes OSPF routing that allows Ansible to reach the ABR routes

# Deploy Phase 1 routers
ansible-playbook playbooks/phase1_deploy.yml

# Verify OSPF is running
ansible phase1_routers -m cisco.ios.ios_command -a "commands='show ip ospf neighbor'"

What Phase 1 accomplishes:

Configures R4, R6 (Area 0) and R7, R9 (Area 1)
Establishes OSPF adjacencies within each area
Creates routing paths that will allow Ansible to reach R5 and R8

Expected output:

R4 ↔ R6 neighbors in Area 0
R7 ↔ R9 neighbors in Area 1 (initially won't form because R8 is not configured yet)

Phase 2: Deploy ABR Routers
After Phase 1, OSPF routing allows Ansible to reach R5 (172.16.47.205) and R8 (10.200.200.208). Now deploy the ABR configuration.

# Test connectivity before deploying
ping 172.16.47.205
ping 10.200.200.208

# Deploy Phase 2 (ABR routers)
ansible-playbook playbooks/phase2_abr_deploy.yml

What Phase 2 accomplishes:

Configures ABR links between R5 and R8
Establishes inter-area OSPF connectivity
Completes the multi-site OSPF topology

Expected output:

R5 becomes ABR (Area 0 and Area 1)
R8 becomes ABR (Area 0 and Area 1)
R5 ↔ R8 adjacency forms on ABR link (203.0.113.0/30)
Inter-area routes (O IA) appear in routing tables

Full Deployment (Both Phases)
# Deploy everything in sequence
ansible-playbook playbooks/phase1_deploy.yml && \
ansible-playbook playbooks/phase2_abr_deploy.yml

Verification
Comprehensive OSPF Check
# Run full verification playbook
ansible-playbook playbooks/verify_ospf.yml
Manual Verification Commands
Check OSPF neighbors:
ansible routers -m cisco.ios.ios_command -a "commands='show ip ospf neighbor'"
Check OSPF routes:
ansible routers -m cisco.ios.ios_command -a "commands='show ip route ospf'"
Check ABR status:
ansible abr_routers -m cisco.ios.ios_command -a "commands='show ip ospf border-routers'"
Test inter-site connectivity:
# From any router, should be able to ping all loopbacks
ansible R4 -m cisco.ios.ios_command -a "commands='ping 9.9.9.9 source loopback0'"


### Expected OSPF Neighbor Relationships

| Router | Expected Neighbors | Area |
|--------|-------------------|------|
| R4 | R5, R6 | 0 |
| R5 | R4, R8 | 0, 1 (ABR) |
| R6 | R4 | 0 |
| R7 | R8 | 1 |
| R8 | R5, R7, R9 | 0, 1 (ABR) |
| R9 | R8 | 1 |

### Expected Route Types

- **O**: Intra-area OSPF routes (within same area)
- **O IA**: Inter-area OSPF routes (between Area 0 and Area 1)

**Area 0 routers should see:**
- O routes to other Area 0 networks
- O IA routes to Area 1 networks

**Area 1 routers should see:**
- O routes to other Area 1 networks
- O IA routes to Area 0 networks

---

## Troubleshooting

### Issue: Cannot reach R5 or R8 from Ansible

**Symptoms:**

fatal: [R5]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect"}
Solution:

Verify Linux routes are configured:

bash   ip route show | grep -E "172.16.47|10.200.200"

Verify EVE-NG IP forwarding is enabled:

bash   ssh root@192.168.33.130
   sysctl net.ipv4.ip_forward

# Should return: net.ipv4.ip_forward = 1

Test connectivity:
bash   ping 172.16.47.205
   ping 10.200.200.208

Check return routes on R5 and R8:
bash   ssh ansible@172.16.47.205
   show ip route | include 192.168.33.0

# Should show static route via 172.16.47.1
Issue: OSPF neighbors not forming
Check interface status:
bashansible routers -m cisco.ios.ios_command -a "commands='show ip ospf interface brief'"

Check OSPF configuration:
bashansible routers -m cisco.ios.ios_command -a "commands='show run | section router ospf'"

Common issues:
Interface down
IP address mismatch
Subnet mask mismatch
Area mismatch
Passive interface incorrectly configured

Issue: Phase 1 completes but R7-R9 don't form adjacency
This is expected! R8 is not configured in Phase 1, so R7 and R9 cannot form a full mesh until Phase 2 is deployed.

fter Phase 2:
ansible R7,R9 -m cisco.ios.ios_command -a "commands='show ip ospf neighbor'"
# Should now see R8 as neighbor

---

## Learning Objectives

This lab demonstrates:

1. **Multi-area OSPF design** - Area 0 (backbone) and Area 1 (stub)
2. **ABR functionality** - R5 and R8 connect different areas
3. **Phased network deployment** - Bootstrap problem solving
4. **Management plane separation** - Out-of-band management network
5. **Ansible automation** - Template-driven configuration
6. **Network routing fundamentals** - Static routes for management, dynamic routes for data

---

## Network Design Decisions Explained

### Why R5 and R8 are not on PNet0?

**Educational purpose:** Demonstrates real-world scenario where not all devices have direct management access. Forces understanding of:
- Routing dependencies
- Bootstrap sequences
- Out-of-band vs in-band management

**Production parallel:** Remote branch routers often don't have direct corporate network access until VPN/MPLS is established.

### Why use static routes for R5/R8 return paths?

**Bootstrap necessity:** OSPF isn't running yet when devices need management access. Static routes provide initial reachability.

**Management best practice:** Management traffic should not depend on production routing protocols.

### Why two deployment phases?

**Dependencies:** R5 and R8 require OSPF routing to be reachable from Ansible. Cannot configure them until OSPF provides the path.

**Real-world parallel:** Network rollouts often happen in phases with dependencies between stages.

---

## Advanced Exercises

Once basic lab is working, try these enhancements:

1. **Add OSPF authentication:**
   - Implement MD5 authentication on all OSPF adjacencies
   - Different keys for Area 0 vs Area 1

2. **Configure Area 1 as stub area:**
   - Reduce routing table size on Area 1 routers
   - Observe LSA filtering at ABRs

3. **Implement route summarization:**
   - Summarize Area 1 routes at R8
   - Observe reduction in Area 0 routing tables

4. **Add OSPF cost manipulation:**
   - Make R5-R8 link preferred path
   - Create backup paths through Area 0

5. **Simulate link failures:**
   - Shutdown interfaces
   - Observe OSPF reconvergence
   - Measure failover times

---

## Files Reference
multi-site-ospf/
├── ansible.cfg
├── README.md (this file)
├── inventory/
│   ├── hosts.yml
│   ├── group_vars/
│   │   ├── all.yml
│   │   ├── area0_routers.yml
│   │   ├── area1_routers.yml
│   │   └── abr_routers.yml
│   └── host_vars/
│       ├── R4.yml
│       ├── R5.yml
│       ├── R6.yml
│       ├── R7.yml
│       ├── R8.yml
│       └── R9.yml
├── roles/
│   ├── base_interfaces/
│   │   ├── tasks/main.yml
│   │   └── templates/interfaces.j2
│   └── ospf/
│       ├── defaults/main.yml
│       ├── tasks/main.yml
│       └── templates/ospf.j2
└── playbooks/
    ├── phase1_deploy.yml
    ├── phase2_abr_deploy.yml
    └── verify_ospf.yml

---

## Support

For issues or questions about this lab:
1. Verify all prerequisites are met
2. Check the troubleshooting section
3. Review Ansible output for specific error messages
4. Verify EVE-NG topology matches diagram exactly

**Common pitfalls:**
- Forgetting to configure Linux routing
- EVE-NG IP forwarding not enabled
- Wrong interface numbers in EVE-NG connections
- DHCP conflicts on PNet1 (should be disabled in router configs)


---

## Deployment Instructions

### Step 1: Apply Export Configs

Apply the export.cfg to each router in EVE-NG (copy-paste into console during initial boot).

### Step 2: Verify Basic Connectivity
# Test Phase 1 routers
ping 172.16.47.204  # R4
ping 172.16.47.206  # R6
ping 10.200.200.207  # R7
ping 10.200.200.209  # R9

# SSH test
ssh ansible@192.168.33.xxx


### Step 3: Run Phase 1 Deployment
cd multi-site-ospf
ansible-playbook playbooks/phase1_deploy.yml

### Step 4: Verify Phase 1 Success
# Check OSPF neighbors formed
ansible phase1_routers -m cisco.ios.ios_command -a "commands='show ip ospf neighbor'"

# Test connectivity to R5 and R8
ping 172.16.47.205
ping 10.200.200.208


### Step 5: Run Phase 2 Deployment
ansible-playbook playbooks/phase2_abr_deploy.yml


### Step 6: Full Verification
ansible-playbook playbooks/verify_ospf.yml


---

**All configurations complete! This gives you a production-grade multi-site OSPF lab with phased deployment demonstrating real-world network bootstrap scenarios.**