# Lab 2A: OSPF Dynamic Routing - Step-by-Step Guide

## Phase 2 Topology: 3-Router OSPF Design

```
                    [Cloud0 - Management]
                            |
                    [Switch - Unmanaged]
                    (192.168.33.0/24)
                            |
        +-------------------+-------------------+
        |                   |                   |
   [R1 - ABR]          [R2 - Core]         [R3 - Edge]
 Gi0/0:.201          Gi0/0:.202          Gi0/0:.203
        |                   |                   |
        |    10.1.12.0/30   |   10.1.23.0/30   |
        |    (Area 0)       |    (Area 1)      |
        +-------[Gi0/1]-----+-----[Gi0/1]------+
        
    Lo0: 1.1.1.1/32    Lo0: 2.2.2.2/32    Lo0: 3.3.3.3/32
    Lo1: 10.10.1.0/24  Lo1: 10.10.2.0/24  Lo1: 10.10.3.0/24
```

### Network Design Details

| Router | Role | OSPF Areas | Management IP | Router ID |
|--------|------|------------|---------------|-----------|
| R1 | ABR (Area Border Router) | Area 0 & 1 | 192.168.33.201 | 1.1.1.1 |
| R2 | Core (Backbone) | Area 0 only | 192.168.33.202 | 2.2.2.2 |
| R3 | Edge | Area 1 only | 192.168.33.203 | 3.3.3.3 |

### Link Design

| Link | Network | R1 Interface | R2 Interface | R3 Interface | Area |
|------|---------|--------------|--------------|--------------|------|
| R1-R2 | 10.1.12.0/30 | Gi0/1: .1 | Gi0/1: .2 | - | 0 |
| R1-R3 | 10.1.13.0/30 | Gi0/2: .1 | - | Gi0/1: .2 | 1 |

---

## Step 1: EVE-NG Topology Setup

### 1.1 Add Devices

1. **Add Management Switch**:
   - Right-click canvas → Add Node → Network → Management (Cloud0)
   - Add a switch (any unmanaged switch from your EVE-NG)

2. **Add 3 Routers**:
   - Right-click canvas → Add Node → Cisco IOSv (or your preferred Cisco router image)
   - Add 3 instances, name them: R1, R2, R3

### 1.2 Create Connections

Connect interfaces **exactly** as shown:

```
Cloud0 (Management) → Switch
Switch → R1 Gi0/0
Switch → R2 Gi0/0
Switch → R3 Gi0/0

R1 Gi0/1 → R2 Gi0/1  (Area 0 link)
R1 Gi0/2 → R3 Gi0/1  (Area 1 link)
```

---

## Step 2: 

### Verification Step

From your Ansible control machine:
```bash
ssh ansible@192.168.33.xxx
```

---

## Step 3: Ansible Directory Structure

Create this directory structure:

```
ospf-lab/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│   |    ├── all.yml
│   |    └── routers.yml
|   ── host_vars/
    ├── R1.yml
    ├── R2.yml
    └── R3.yml
├── roles/
│   ├── base_interfaces/
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   └── templates/
│   │       └── interfaces.j2
│   └── ospf/
│       ├── tasks/
│       │   └── main.yml
│       ├── templates/
│       │   └── ospf.j2
│       └── defaults/
│           └── main.yml
├── playbooks/
│   └── deploy_ospf.yml
```

---

### Run the Playbook

```bash
# Full deployment
ansible-playbook playbooks/deploy_ospf.yml

# Deploy only interfaces
ansible-playbook playbooks/deploy_ospf.yml --tags interfaces

# Deploy only OSPF
ansible-playbook playbooks/deploy_ospf.yml --tags ospf

# Run verification only
ansible-playbook playbooks/deploy_ospf.yml --tags verify
```

### Manual Verification Commands

After Ansible runs, SSH to each router and verify:

```bash

show ip route ospf
# Should see routes to 10.10.2.0/24, 10.10.3.0/24, 2.2.2.2/32, 3.3.3.3/32

show ip ospf database
# Should show LSAs for all routers

# Test connectivity
ping 10.10.2.1 source loopback1
ping 10.10.3.1 source loopback1
```

```bash
# On R2
show ip ospf neighbor
# Should see: R1 (via 10.1.12.1)

show ip route ospf
# Should see IA (inter-area) routes to Area 1 networks
```

```bash
# On R3
show ip ospf neighbor
# Should see: R1 (via 10.1.13.1)

show ip route ospf
# Should see IA routes to Area 0 networks
```

---

## Step 9: Expected OSPF Behavior

### Neighbor Relationships

- **R1 ↔ R2**: FULL state (Area 0)
- **R1 ↔ R3**: FULL state (Area 1)
- R2 and R3 will NOT be neighbors (different areas, no direct link)

### Route Types

- **O** = OSPF intra-area routes (within same area)
- **O IA** = OSPF inter-area routes (between areas)
- R1 is the ABR, so it advertises routes between Area 0 and Area 1

### Cost Calculation

With reference bandwidth 10000:
- Ethernet cost = 10000/1000 = 10
- Routes will show cumulative cost

---

## Troubleshooting Tips

### Issue: OSPF Neighbors Not Forming

```bash
# Check OSPF is running
show ip ospf

# Check interfaces are in OSPF
show ip ospf interface

# Check for mismatched timers
show ip ospf interface Ethernet0/1

# Common fixes:
router ospf 1
 no passive-interface Ethernet0/1
```

### Issue: Routes Missing

```bash
# Verify network statements
show running-config | section ospf

# Check OSPF database
show ip ospf database

# Verify area assignments
show ip ospf interface brief
```
