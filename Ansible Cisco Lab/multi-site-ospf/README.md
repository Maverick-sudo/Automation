# Multi-Site OSPF Lab - Copilot Instructions

## Project Overview

**Goal:** Build a production-grade multi-area OSPF network across two geographically separated sites (Area 0 and Area 1) connected via Area Border Routers (ABRs), using Ansible automation with phased deployment to solve bootstrap connectivity challenges.

---

## Network Architecture

### Three-Network Design

**PNet0 (192.168.33.0/24)** - Management Network (NAT)
- Purpose: Ansible SSH management, internet access
- Connected routers: R4, R6, R7, R9
- EVE-NG interface: 192.168.33.130

**PNet1 (172.16.47.0/24)** - Site A / Area 0 Campus (Host-only with DHCP)
- Purpose: Area 0 data plane
- Connected routers: R4, R6
- EVE-NG gateway: 172.16.47.129

**PNet2 (10.200.200.0/24)** - Site B / Area 1 Campus (Host-only without DHCP)
- Purpose: Area 1 data plane
- Connected routers: R7, R9
- EVE-NG gateway: 10.200.200.129

### Topology Summary

```
Site A (Area 0):          ABRs:              Site B (Area 1):
R4 ←→ R6                R5 ←→ R8            R7 ←→ R9
  ↓                      ↓   ↓                 ↓
PNet1               (not on PNet)           PNet2
```

**Key design:** R5 and R8 (ABRs) are NOT directly connected to management network (PNet0). They are reachable only through OSPF routing after Phase 1 deployment.

---

## Host Configuration (Already Complete)

### Linux Ansible Control Node Routes

```bash
# Routes to reach Site A and Site B via EVE-NG
ip route add 172.16.47.0/24 via 192.168.33.130
ip route add 10.200.200.0/24 via 192.168.33.130
```

### EVE-NG Internal Routing

```bash
# EVE-NG forwarding between networks
pnet0: 192.168.33.130  → Management
pnet1: 172.16.47.129   → Site A gateway
pnet2: 10.200.200.129  → Site B gateway

# IP forwarding enabled
net.ipv4.ip_forward=1
```

---

## Implementation Strategy

### Phased Deployment Approach

**Phase 1: Bootstrap Core Routers**
- Deploy: R4, R6 (Area 0) and R7, R9 (Area 1)
- These routers are directly reachable from Ansible (192.168.33.x)
- Establish OSPF within each area
- Creates routing paths that enable Ansible to reach R5 and R8

**Phase 2: Deploy ABR Routers**
- Deploy: R5 and R8 (ABRs)
- Now reachable via OSPF routing: R5 at 10.10.20.1, R8 at 10.10.10.1
- Configure ABR interconnection link (203.0.113.0/30)
- Establish inter-area OSPF routing

**Why phased?** R5 and R8 are only reachable AFTER OSPF provides routing. Cannot configure them until Phase 1 establishes connectivity.

---

## Router Addressing

### Management IPs (for Ansible SSH)

| Router | Management IP | Network |
|--------|--------------|---------|
| R4 | 192.168.33.204 | PNet0 |
| R5 | 10.10.20.1 (via OSPF) | Area 0 data |
| R6 | 192.168.33.206 | PNet0 |
| R7 | 192.168.33.207 | PNet0 |
| R8 | 10.10.10.1 (via OSPF) | Area 1 data |
| R9 | 192.168.33.209 | PNet0 |

### Data Plane Networks

- Area 0 links: 10.10.20.0/30, 10.10.20.4/30
- Area 1 links: 10.10.10.0/30, 10.10.10.4/30
- ABR link: 203.0.113.0/30
- Loopbacks: X.X.X.X/32 (OSPF router IDs)

---

## Ansible Playbooks

1. **phase1_deploy.yml** - Deploy R4, R6, R7, R9 with OSPF
2. **phase2_abr_deploy.yml** - Deploy R5, R8 after connectivity established
3. **verify_ospf.yml** - Comprehensive verification across all sites

### Ansible Roles

1. **base_interfaces** - Configure router interfaces from Jinja2 templates
2. **ospf** - Deploy OSPF configuration with area assignments

### Key Requirements

- R5 and R8 must have return routes to 192.168.33.0/24 in export.cfg
- R4, R6 default route: 172.16.47.129
- R7, R9 default route: 10.200.200.129
- R5, R8 specific route: 192.168.33.0/24 via their Area 0/1 neighbors
- OSPF passive interfaces on loopbacks simulating LANs

---

## Expected Outcomes

**After Phase 1:**
- R4 ↔ R6 OSPF adjacency (Area 0)
- R7 ↔ R9 adjacency may not form (R8 missing)
- Ansible can now reach 10.10.20.1 (R5) and 10.10.10.1 (R8)

**After Phase 2:**
- R5 ↔ R8 OSPF adjacency on ABR link (Area 0 ↔ Area 1)
- All routers have full OSPF neighbor adjacencies
- Inter-area routes (O IA) appear in routing tables
- Site A can communicate with Site B

**Verification:**
- All neighbors in FULL state
- R5 and R8 show as ABRs
- Ping connectivity between all loopbacks
- Inter-area routes present

---

## File Structure Reference

```
multi-site-ospf/
├── inventory/
│   ├── hosts.yml (phase1_routers, phase2_routers groups)
│   ├── host_vars/ (R4.yml through R9.yml)
│   └── group_vars/
├── roles/
│   ├── base_interfaces/
│   └── ospf/
└── playbooks/
    ├── phase1_deploy.yml
    ├── phase2_abr_deploy.yml
    └── verify_ospf.yml
```

---

## Coding Agent Tasks

1. Review existing example configurations in `host_vars/` for addressing scheme
2. Review existing playbooks respect phase ordering (phase1 must complete before phase2)
3. Review existing configurations Implemented in comprehensive verification that tests:
   - OSPF neighbor states
   - ABR functionality
   - Inter-area routing
   - End-to-end reachability

---

## Critical Design Decisions

**Why R5/R8 aren't on PNet0:** Demonstrates real-world bootstrap problem where remote devices aren't directly management-reachable until routing is established.

**Why phased deployment:** Teaches dependency management and network rollout sequencing.

**Why three separate networks:** Separates management plane (PNet0) from data planes (PNet1/PNet2), realistic multi-site architecture.

---

## Success Criteria

- [ ] Phase 1 deploys successfully to R4, R6, R7, R9
- [ ] Ansible can reach R5 and R8 after Phase 1
- [ ] Phase 2 deploys successfully to R5, R8
- [ ] All OSPF neighbors achieve FULL state
- [ ] Inter-area routes appear in routing tables
- [ ] Ping test succeeds between all router loopbacks
- [ ] R5 and R8 identified as ABRs in OSPF output

---

**Note to Agent:** All network infrastructure is configured. Focus on Ansible automation logic, Jinja2 templating, and OSPF configuration accuracy. Reference existing example files for syntax patterns.


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

### Step 1: Linux Ansible Control Node Setup

**CRITICAL:** The Ansible control node must have routes to reach PNet1 and PNet2 networks via EVE-NG.

#### Add Static Routes (Temporary)
```bash
# Add routes to lab networks
sudo ip route add 172.16.47.0/24 via 192.168.33.130
sudo ip route add 10.200.200.0/24 via 192.168.33.130

# Verify routes are installed
ip route show | grep -E "172.16.47|10.200.200"
```

**Expected output:**
```
10.200.200.0/24 via 192.168.33.130 dev ens3
172.16.47.0/24 via 192.168.33.130 dev ens3
```

#### Make Routes Persistent

**For Debian with NetworkManager:**
```bash
# Create dispatcher script
sudo nano /etc/NetworkManager/dispatcher.d/99-eve-routes
```

Add this content:
```bash
#!/bin/bash
if [ "$2" = "up" ]; then
    ip route add 10.200.200.0/24 via 192.168.33.130 2>/dev/null || true
    ip route add 172.16.47.0/24 via 192.168.33.130 2>/dev/null || true
fi
```

Make executable:
```bash
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-eve-routes
```

**For Ubuntu with netplan:**
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

**For Debian with /etc/network/interfaces:**
```bash
sudo nano /etc/network/interfaces
```

Add after your primary interface:
```
# Routes to EVE-NG lab networks
up ip route add 172.16.47.0/24 via 192.168.33.130 || true
up ip route add 10.200.200.0/24 via 192.168.33.130 || true
```

---

### Step 2: EVE-NG Host Network Configuration

**CRITICAL:** EVE-NG must forward packets between pnet interfaces and enable proper NAT/masquerading.

#### Enable IP Forwarding (REQUIRED!)
```bash
# Enable immediately
sudo sysctl -w net.ipv4.ip_forward=1

# Verify it's enabled
sysctl net.ipv4.ip_forward
# Should show: net.ipv4.ip_forward = 1

# Make persistent across reboots
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

#### Disable Reverse Path Filtering
```bash
# Disable on all pnet interfaces
sudo sysctl -w net.ipv4.conf.pnet0.rp_filter=0
sudo sysctl -w net.ipv4.conf.pnet1.rp_filter=0
sudo sysctl -w net.ipv4.conf.pnet2.rp_filter=0

# Make persistent
echo "net.ipv4.conf.pnet0.rp_filter=0" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.conf.pnet1.rp_filter=0" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.conf.pnet2.rp_filter=0" | sudo tee -a /etc/sysctl.conf
```

#### Configure NAT/Masquerading Rules
```bash
# NAT for routers reaching management network (pnet0)
sudo iptables -t nat -A POSTROUTING -s 172.16.47.0/24 -o pnet0 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o pnet0 -j MASQUERADE

# NAT for Ansible control node reaching lab networks
sudo iptables -t nat -A POSTROUTING -s 192.168.33.0/24 -o pnet1 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.33.0/24 -o pnet2 -j MASQUERADE

# Verify all 4 NAT rules
sudo iptables -t nat -L POSTROUTING -n -v
```

**Expected NAT output:**
```
Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MASQUERADE all  --  *      pnet0   172.16.47.0/24       0.0.0.0/0
    0     0 MASQUERADE all  --  *      pnet0   10.200.200.0/24      0.0.0.0/0
    0     0 MASQUERADE all  --  *      pnet1   192.168.33.0/24      0.0.0.0/0
    0     0 MASQUERADE all  --  *      pnet2   192.168.33.0/24      0.0.0.0/0
```

#### Configure FORWARD Rules
```bash
# Allow traffic between all pnet interfaces
sudo iptables -A FORWARD -i pnet1 -o pnet0 -j ACCEPT
sudo iptables -A FORWARD -i pnet2 -o pnet0 -j ACCEPT
sudo iptables -A FORWARD -i pnet0 -o pnet1 -j ACCEPT
sudo iptables -A FORWARD -i pnet0 -o pnet2 -j ACCEPT

# Verify FORWARD rules
sudo iptables -L FORWARD -n -v
```

#### Save iptables Rules Permanently
```bash
# Create directory if it doesn't exist
sudo mkdir -p /etc/iptables

# Save current rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Install iptables-persistent for auto-restore on boot
sudo apt-get update
sudo apt-get install -y iptables-persistent

# Or manually restore on boot by adding to /etc/rc.local:
# iptables-restore < /etc/iptables/rules.v4
```

---

### Step 3: Verify Connectivity

**From Ansible Control Node (Debian):**
```bash
# Test ping to EVE-NG gateways
ping -c3 192.168.33.130  # EVE-NG pnet0
ping -c3 172.16.47.129   # EVE-NG pnet1 gateway
ping -c3 10.200.200.129  # EVE-NG pnet2 gateway

# Test ping to routers
ping -c3 172.16.47.204   # R4
ping -c3 172.16.47.206   # R6
ping -c3 10.200.200.207  # R7
ping -c3 10.200.200.209  # R9

# Test SSH connectivity
ssh ansible@172.16.47.204  # Password: ansible123
ssh ansible@10.200.200.207
```

**All pings and SSH should work before proceeding!**

---

### Troubleshooting Connectivity Issues

#### Issue: Routes disappear after Debian reboot
**Cause:** Routes added with `ip route add` are not persistent.  
**Solution:** Follow Step 1 to make routes persistent using NetworkManager dispatcher, netplan, or /etc/network/interfaces.

#### Issue: Ping to routers times out, but EVE-NG gateways work
**Symptoms:**
```bash
ping 172.16.47.129  # Works ✅
ping 172.16.47.204  # Timeout ❌
```

**Diagnosis:**
```bash
# On EVE-NG, check IP forwarding
sysctl net.ipv4.ip_forward
# If shows 0, forwarding is disabled!
```

**Solution:** Enable IP forwarding on EVE-NG (see Step 2).

#### Issue: Packets reach router but no reply
**Diagnosis:**
```bash
# On EVE-NG
sudo tcpdump -n -i pnet1 'icmp and host 172.16.47.204'
# Shows only requests, no replies = router can't reach back to Debian
```

**Solution:** Router needs return route to management network (already in export.cfg):
```cisco
ip route 0.0.0.0 0.0.0.0 172.16.47.129  # R4, R6
ip route 0.0.0.0 0.0.0.0 10.200.200.129 # R7, R9
```

#### Issue: tcpdump shows 0 packets on pnet interfaces
**Diagnosis:** iptables FORWARD rules blocking traffic.

**Solution:** Add FORWARD ACCEPT rules (see Step 2).

#### Quick Diagnostic Commands
```bash
# On Debian - check routes
ip route show

# On EVE-NG - check forwarding and NAT
sysctl net.ipv4.ip_forward
sudo iptables -t nat -L POSTROUTING -n -v
sudo iptables -L FORWARD -n -v

# Watch packet flow
sudo tcpdump -n -i pnet0 'host 192.168.33.149'
```

---

### Complete Setup Verification Checklist

Before deploying OSPF, verify:

- [ ] Debian can ping EVE-NG gateways (192.168.33.130, 172.16.47.129, 10.200.200.129)
- [ ] Debian can ping all Phase 1 routers (R4, R6, R7, R9)
- [ ] SSH works to all Phase 1 routers (`ssh ansible@<router-ip>`)
- [ ] Routes persist after Debian reboot
- [ ] EVE-NG `net.ipv4.ip_forward = 1`
- [ ] EVE-NG has 4 NAT MASQUERADE rules
- [ ] EVE-NG has 4 FORWARD ACCEPT rules
- [ ] iptables rules persist after EVE-NG reboot


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