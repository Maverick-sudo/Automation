# Complete 6-Router OSPF Lab - Production-Grade Setup

## Step 1: Create Directory Structure (One-Liner)

```bash
mkdir -p ospf-lab-6r/{inventory/{group_vars,host_vars},roles/{base_interfaces/{tasks,templates},ospf/{tasks,templates,defaults}},playbooks} && cd ospf-lab-6r && touch ansible.cfg inventory/{hosts.yml,group_vars/{all.yml,hq_routers.yml,branch_routers.yml,routers.yml},host_vars/{R3.yml,R4.yml,R5.yml,R6.yml,R7.yml,R8.yml}} roles/base_interfaces/{tasks/main.yml,templates/interfaces.j2} roles/ospf/{tasks/main.yml,templates/ospf.j2,defaults/main.yml} playbooks/{deploy_ospf.yml,verify_ospf.yml,rollback.yml}
```

---

## Step 2: Network Design Documentation

### Management Networks

| Segment | Network | Gateway | Devices |
|---------|---------|---------|---------|
| HQ/Core | 192.168.33.0/24 | 192.168.33.1 | R3, R4, R5, Linux(e0) |
| Branches | 192.168.33.0/24 | 192.168.33.1 | R6, R7, R8, Linux(e1) |

### OSPF Area Assignment

| Router | Role | OSPF Areas | Router ID | Management IP |
|--------|------|------------|-----------|---------------|
| R3 | ABR (HQ-Branch Link) | Area 0, Area 1 | 3.3.3.3 | 192.168.33.203 |
| R4 | Core/Backbone | Area 0 | 4.4.4.4 | 192.168.33.204 |
| R5 | ABR (HQ-Branch Link) | Area 0, Area 1 | 5.5.5.5 | 192.168.33.205 |
| R6 | Branch Router | Area 1 | 6.6.6.6 | 192.168.33.206 |
| R7 | Branch Router | Area 1 | 7.7.7.7 | 192.168.33.207 |
| R8 | Branch Router | Area 1 | 8.8.8.8 | 192.168.33.208 |

### Link Addressing (Point-to-Point /30 Links)

| Link | Network | Router A | IP A | Router B | IP B | Area |
|------|---------|----------|------|----------|------|------|
| HQ: R3-R4 | 10.1.1.20/30 | R3 | 10.1.1.21 | R4 | 10.1.1.22 | 0 |
| HQ: R4-R5 | 10.1.1.16/30 | R4 | 10.1.1.17 | R5 | 10.1.1.18 | 0 |
| ABR: R3-R6 | 10.1.1.0/30 | R3 | 10.1.1.1 | R6 | 10.1.1.2 | 1 |
| ABR: R5-R8 | 10.1.1.12/30 | R5 | 10.1.1.13 | R8 | 10.1.1.14 | 1 |
| Branch: R6-R7 | 10.1.1.4/30 | R6 | 10.1.1.5 | R7 | 10.1.1.6 | 1 |
| Branch: R7-R8 | 10.1.1.8/30 | R7 | 10.1.1.9 | R8 | 10.1.1.10 | 1 |

---

## Step 3: Linux-MasterNode Network Configuration

### Configure Dual NICs

```bash
# Check interface names
ip link show

# Configure e0 for HQ management
sudo ip addr add 192.168.33.10/24 dev e0
sudo ip link set e0 up

# Configure e1 for Branch management
sudo ip addr add 192.168.33.10/24 dev e1
sudo ip link set e1 up

# Verify
ip addr show
```

### Make Persistent (Netplan)

Create `/etc/netplan/99-ansible-mgmt.yaml`:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    e0:
      addresses:
        - 192.168.33.10/24
      dhcp4: no
      
    e1:
      addresses:
        - 192.168.33.10/24
      dhcp4: no
```

Apply:
```bash
sudo netplan apply
sudo systemctl restart systemd-networkd

# Test connectivity
ping -c 2 192.168.33.203  # R3
ping -c 2 192.168.33.206  # R6
```

---

## Step 4: Router Startup Configurations

Apply these **manually** on each router console (only management interface).

### R3 Startup Config

```cisco
hostname R3
!
ip domain-name lab.local
crypto key generate rsa modulus 2048
!
username ansible privilege 15 secret cisco
!
interface Ethernet0/0
 description MGMT_HQ_NETWORK
 no ip address dhcp
 ip address 192.168.33.203 255.255.255.0
 no shutdown
!
interface Ethernet0/1
 description TO_R6_AREA1
 no shutdown
!
interface Ethernet0/2
 description TO_R4_AREA0
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 192.168.33.1
!
line vty 0 4
 login local
 transport input ssh
!
end
write memory
```

### R4 Startup Config

```cisco
hostname R4
!
ip domain-name lab.local
crypto key generate rsa modulus 2048
!
username ansible privilege 15 secret cisco
!
interface Ethernet0/0
 description MGMT_HQ_NETWORK
 no ip address dhcp
 ip address 192.168.33.204 255.255.255.0
 no shutdown
!
interface Ethernet0/2
 description TO_R3_AREA0
 no shutdown
!
interface Ethernet0/3
 description TO_R5_AREA0
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 192.168.33.1
!
line vty 0 4
 login local
 transport input ssh
!
end
write memory
```

### R5 Startup Config

```cisco
hostname R5
!
ip domain-name lab.local
crypto key generate rsa modulus 2048
!
username ansible privilege 15 secret cisco
!
interface Ethernet0/0
 description MGMT_HQ_NETWORK
 no ip address dhcp
 ip address 192.168.33.205 255.255.255.0
 no shutdown
!
interface Ethernet0/1
 description TO_R8_AREA1
 no shutdown
!
interface Ethernet0/3
 description TO_R4_AREA0
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 192.168.33.1
!
line vty 0 4
 login local
 transport input ssh
!
end
write memory
```

### R6 Startup Config

```cisco
hostname R6
!
ip domain-name lab.local
crypto key generate rsa modulus 2048
!
username ansible privilege 15 secret cisco
!
interface Ethernet0/0
 description MGMT_BRANCH_NETWORK
 no ip address dhcp
 ip address 192.168.33.206 255.255.255.0
 no shutdown
!
interface Ethernet0/1
 description TO_R3_AREA1
 no shutdown
!
interface Ethernet0/2
 description TO_R7_AREA1
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 192.168.33.1
!
line vty 0 4
 login local
 transport input ssh
!
end
write memory
```

### R7 Startup Config

```cisco
hostname R7
!
ip domain-name lab.local
crypto key generate rsa modulus 2048
!
username ansible privilege 15 secret cisco
!
interface Ethernet0/0
 description MGMT_BRANCH_NETWORK
 no ip address dhcp
 ip address 192.168.33.207 255.255.255.0
 no shutdown
!
interface Ethernet0/2
 description TO_R6_AREA1
 no shutdown
!
interface Ethernet0/3
 description TO_R8_AREA1
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 192.168.33.1
!
line vty 0 4
 login local
 transport input ssh
!
end
write memory
```

### R8 Startup Config

```cisco
hostname R8
!
ip domain-name lab.local
crypto key generate rsa modulus 2048
!
username ansible privilege 15 secret cisco
!
interface Ethernet0/0
 description MGMT_BRANCH_NETWORK
 no ip address dhcp
 ip address 192.168.33.208 255.255.255.0
 no shutdown
!
interface Ethernet0/1
 description TO_R5_AREA1
 no shutdown
!
interface Ethernet0/3
 description TO_R7_AREA1
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 192.168.33.1
!
line vty 0 4
 login local
 transport input ssh
!
end
write memory
```

**Verify SSH Access:**
```bash
ssh ansible@192.168.33.203  # R3
ssh ansible@192.168.33.204  # R4
ssh ansible@192.168.33.205  # R5
ssh ansible@192.168.33.206  # R6
ssh ansible@192.168.33.207  # R7
ssh ansible@192.168.33.208  # R8
```

---

## Step 5: Ansible Configuration Files

### ansible.cfg

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
host_key_checking = False
retry_files_enabled = False
gathering = explicit
stdout_callback = yaml
timeout = 60

[persistent_connection]
command_timeout = 60
connect_timeout = 60
connect_retry_timeout = 30
```

### inventory/hosts.yml

```yaml
---
all:
  children:
    hq_routers:
      hosts:
        R3:
          ansible_host: 192.168.33.203
        R4:
          ansible_host: 192.168.33.204
        R5:
          ansible_host: 192.168.33.205
    
    branch_routers:
      hosts:
        R6:
          ansible_host: 192.168.33.206
        R7:
          ansible_host: 192.168.33.207
        R8:
          ansible_host: 192.168.33.208
    
    routers:
      children:
        hq_routers:
        branch_routers:
```

### inventory/group_vars/all.yml

```yaml
---
# Global connection settings
ansible_connection: ansible.netcommon.network_cli
ansible_network_os: cisco.ios.ios
ansible_user: ansible
ansible_password: cisco
ansible_become: yes
ansible_become_method: enable
```

### inventory/group_vars/routers.yml

```yaml
---
# OSPF Global Settings
ospf_process_id: 1
ospf_reference_bandwidth: 10000  # 10 Gbps
```

### inventory/group_vars/hq_routers.yml

```yaml
---
# HQ/Core specific settings
site_location: "Headquarters"
ospf_default_metric: 10
```

### inventory/group_vars/branch_routers.yml

```yaml
---
# Branch specific settings
site_location: "Remote Branch"
ospf_default_metric: 100
```

---

## Step 6: Host Variables (Per-Router Configuration)

### inventory/host_vars/R3.yml

```yaml
---
hostname: R3
ospf_router_id: 3.3.3.3

# R3 is an ABR - connects Area 0 (HQ) to Area 1 (Branches)
interfaces:
  - name: Ethernet0/1
    description: "TO_R6_BRANCH_AREA1"
    ipv4_address: 10.1.1.1
    ipv4_netmask: 255.255.255.252
    
  - name: Ethernet0/2
    description: "TO_R4_HQ_AREA0"
    ipv4_address: 10.1.1.21
    ipv4_netmask: 255.255.255.252

  - name: Loopback0
    description: "ROUTER_ID"
    ipv4_address: 3.3.3.3
    ipv4_netmask: 255.255.255.255
    
  - name: Loopback1
    description: "SIMULATED_HQ_NETWORK"
    ipv4_address: 10.10.3.1
    ipv4_netmask: 255.255.255.0

# OSPF Configuration - R3 is ABR
ospf_networks:
  # Area 0 networks
  - network: 10.1.1.20
    wildcard: 0.0.0.3
    area: 0
  
  - network: 3.3.3.3
    wildcard: 0.0.0.0
    area: 0
    
  - network: 10.10.3.0
    wildcard: 0.0.0.255
    area: 0
  
  # Area 1 networks (ABR link)
  - network: 10.1.1.0
    wildcard: 0.0.0.3
    area: 1

ospf_passive_interfaces:
  - Loopback1
```

### inventory/host_vars/R4.yml

```yaml
---
hostname: R4
ospf_router_id: 4.4.4.4

# R4 is Core/Backbone - Area 0 only
interfaces:
  - name: Ethernet0/2
    description: "TO_R3_HQ_AREA0"
    ipv4_address: 10.1.1.22
    ipv4_netmask: 255.255.255.252
    
  - name: Ethernet0/3
    description: "TO_R5_HQ_AREA0"
    ipv4_address: 10.1.1.17
    ipv4_netmask: 255.255.255.252

  - name: Loopback0
    description: "ROUTER_ID"
    ipv4_address: 4.4.4.4
    ipv4_netmask: 255.255.255.255
    
  - name: Loopback1
    description: "SIMULATED_HQ_NETWORK"
    ipv4_address: 10.10.4.1
    ipv4_netmask: 255.255.255.0

# OSPF Configuration - R4 is pure Area 0
ospf_networks:
  - network: 10.1.1.20
    wildcard: 0.0.0.3
    area: 0
    
  - network: 10.1.1.16
    wildcard: 0.0.0.3
    area: 0
  
  - network: 4.4.4.4
    wildcard: 0.0.0.0
    area: 0
    
  - network: 10.10.4.0
    wildcard: 0.0.0.255
    area: 0

ospf_passive_interfaces:
  - Loopback1
```

### inventory/host_vars/R5.yml

```yaml
---
hostname: R5
ospf_router_id: 5.5.5.5

# R5 is an ABR - connects Area 0 (HQ) to Area 1 (Branches)
interfaces:
  - name: Ethernet0/1
    description: "TO_R8_BRANCH_AREA1"
    ipv4_address: 10.1.1.13
    ipv4_netmask: 255.255.255.252
    
  - name: Ethernet0/3
    description: "TO_R4_HQ_AREA0"
    ipv4_address: 10.1.1.18
    ipv4_netmask: 255.255.255.252

  - name: Loopback0
    description: "ROUTER_ID"
    ipv4_address: 5.5.5.5
    ipv4_netmask: 255.255.255.255
    
  - name: Loopback1
    description: "SIMULATED_HQ_NETWORK"
    ipv4_address: 10.10.5.1
    ipv4_netmask: 255.255.255.0

# OSPF Configuration - R5 is ABR
ospf_networks:
  # Area 0 networks
  - network: 10.1.1.16
    wildcard: 0.0.0.3
    area: 0
  
  - network: 5.5.5.5
    wildcard: 0.0.0.0
    area: 0
    
  - network: 10.10.5.0
    wildcard: 0.0.0.255
    area: 0
  
  # Area 1 networks (ABR link)
  - network: 10.1.1.12
    wildcard: 0.0.0.3
    area: 1

ospf_passive_interfaces:
  - Loopback1
```

### inventory/host_vars/R6.yml

```yaml
---
hostname: R6
ospf_router_id: 6.6.6.6

# R6 is Branch Router - Area 1 only
interfaces:
  - name: Ethernet0/1
    description: "TO_R3_ABR_AREA1"
    ipv4_address: 10.1.1.2
    ipv4_netmask: 255.255.255.252
    
  - name: Ethernet0/2
    description: "TO_R7_BRANCH_AREA1"
    ipv4_address: 10.1.1.5
    ipv4_netmask: 255.255.255.252

  - name: Loopback0
    description: "ROUTER_ID"
    ipv4_address: 6.6.6.6
    ipv4_netmask: 255.255.255.255
    
  - name: Loopback1
    description: "SIMULATED_BRANCH_NETWORK"
    ipv4_address: 10.10.6.1
    ipv4_netmask: 255.255.255.0

# OSPF Configuration - R6 is pure Area 1
ospf_networks:
  - network: 10.1.1.0
    wildcard: 0.0.0.3
    area: 1
    
  - network: 10.1.1.4
    wildcard: 0.0.0.3
    area: 1
  
  - network: 6.6.6.6
    wildcard: 0.0.0.0
    area: 1
    
  - network: 10.10.6.0
    wildcard: 0.0.0.255
    area: 1

ospf_passive_interfaces:
  - Loopback1
```

### inventory/host_vars/R7.yml

```yaml
---
hostname: R7
ospf_router_id: 7.7.7.7

# R7 is Branch Router - Area 1 only
interfaces:
  - name: Ethernet0/2
    description: "TO_R6_BRANCH_AREA1"
    ipv4_address: 10.1.1.6
    ipv4_netmask: 255.255.255.252
    
  - name: Ethernet0/3
    description: "TO_R8_BRANCH_AREA1"
    ipv4_address: 10.1.1.9
    ipv4_netmask: 255.255.255.252

  - name: Loopback0
    description: "ROUTER_ID"
    ipv4_address: 7.7.7.7
    ipv4_netmask: 255.255.255.255
    
  - name: Loopback1
    description: "SIMULATED_BRANCH_NETWORK"
    ipv4_address: 10.10.7.1
    ipv4_netmask: 255.255.255.0

# OSPF Configuration - R7 is pure Area 1
ospf_networks:
  - network: 10.1.1.4
    wildcard: 0.0.0.3
    area: 1
    
  - network: 10.1.1.8
    wildcard: 0.0.0.3
    area: 1
  
  - network: 7.7.7.7
    wildcard: 0.0.0.0
    area: 1
    
  - network: 10.10.7.0
    wildcard: 0.0.0.255
    area: 1

ospf_passive_interfaces:
  - Loopback1
```

### inventory/host_vars/R8.yml

```yaml
---
hostname: R8
ospf_router_id: 8.8.8.8

# R8 is Branch Router - Area 1 only
interfaces:
  - name: Ethernet0/1
    description: "TO_R5_ABR_AREA1"
    ipv4_address: 10.1.1.14
    ipv4_netmask: 255.255.255.252
    
  - name: Ethernet0/3
    description: "TO_R7_BRANCH_AREA1"
    ipv4_address: 10.1.1.10
    ipv4_netmask: 255.255.255.252

  - name: Loopback0
    description: "ROUTER_ID"
    ipv4_address: 8.8.8.8
    ipv4_netmask: 255.255.255.255
    
  - name: Loopback1
    description: "SIMULATED_BRANCH_NETWORK"
    ipv4_address: 10.10.8.1
    ipv4_netmask: 255.255.255.0

# OSPF Configuration - R8 is pure Area 1
ospf_networks:
  - network: 10.1.1.12
    wildcard: 0.0.0.3
    area: 1
    
  - network: 10.1.1.8
    wildcard: 0.0.0.3
    area: 1
  
  - network: 8.8.8.8
    wildcard: 0.0.0.0
    area: 1
    
  - network: 10.10.8.0
    wildcard: 0.0.0.255
    area: 1

ospf_passive_interfaces:
  - Loopback1
```

---

## Step 7: Ansible Roles (Reusable Logic)

### roles/base_interfaces/tasks/main.yml

```yaml
---
- name: Configure router hostname
  cisco.ios.ios_config:
    lines:
      - "hostname {{ hostname }}"

- name: Configure interfaces from template
  cisco.ios.ios_config:
    src: interfaces.j2
  notify: save config

- name: Wait for interfaces to come up
  pause:
    seconds: 5

- name: Verify interface status
  cisco.ios.ios_command:
    commands:
      - show ip interface brief
  register: interface_status

- name: Display interface status
  debug:
    msg: "{{ interface_status.stdout_lines[0] }}"
```

### roles/base_interfaces/templates/interfaces.j2

```jinja
{% for interface in interfaces %}
!
interface {{ interface.name }}
 description {{ interface.description }}
 ip address {{ interface.ipv4_address }} {{ interface.ipv4_netmask }}
 no shutdown
{% endfor %}
!
```

### roles/ospf/defaults/main.yml

```yaml
---
# Default OSPF settings
ospf_process_id: 1
ospf_reference_bandwidth: 10000
ospf_passive_interfaces: []
```

### roles/ospf/tasks/main.yml

```yaml
---
- name: Deploy OSPF configuration from template
  cisco.ios.ios_config:
    src: ospf.j2
  notify: save config

- name: Wait for OSPF to converge
  pause:
    seconds: 15
    prompt: "Waiting for OSPF adjacencies to form..."

- name: Verify OSPF neighbors
  cisco.ios.ios_command:
    commands:
      - show ip ospf neighbor
  register: ospf_neighbors
  retries: 3
  delay: 5
  until: ospf_neighbors is succeeded

- name: Display OSPF neighbors
  debug:
    msg: "{{ ospf_neighbors.stdout_lines[0] }}"

- name: Verify OSPF database
  cisco.ios.ios_command:
    commands:
      - show ip ospf database
  register: ospf_database

- name: Display OSPF database summary
  debug:
    msg: "{{ ospf_database.stdout_lines[0] }}"

- name: Verify OSPF routes
  cisco.ios.ios_command:
    commands:
      - show ip route ospf
  register: ospf_routes

- name: Display OSPF routes
  debug:
    msg: "{{ ospf_routes.stdout_lines[0] }}"
```

### roles/ospf/templates/ospf.j2

```jinja
!
router ospf {{ ospf_process_id }}
 router-id {{ ospf_router_id }}
 auto-cost reference-bandwidth {{ ospf_reference_bandwidth }}
 log-adjacency-changes
{% for network in ospf_networks %}
 network {{ network.network }} {{ network.wildcard }} area {{ network.area }}
{% endfor %}
{% if ospf_passive_interfaces is defined and ospf_passive_interfaces | length > 0 %}
{% for interface in ospf_passive_interfaces %}
 passive-interface {{ interface }}
{% endfor %}
{% endif %}
!
```

---

## Step 8: Playbooks

### playbooks/deploy_ospf.yml

```yaml
---
- name: Deploy 6-Router OSPF Lab Configuration
  hosts: routers
  gather_facts: no
  
  handlers:
    - name: save config
      cisco.ios.ios_config:
        save_when: always

  tasks:
    - name: Gather device facts
      cisco.ios.ios_facts:
        gather_subset: min
      
    - name: Display router info
      debug:
        msg: "Configuring {{ inventory_hostname }} - {{ ansible_net_version }}"

    - name: Apply base interface configuration
      include_role:
        name: base_interfaces
      tags: ['interfaces', 'base']

    - name: Apply OSPF configuration
      include_role:
        name: ospf
      tags: ['ospf', 'routing']

    - name: Final verification - OSPF interface status
      cisco.ios.ios_command:
        commands:
          - show ip ospf interface brief
      register: ospf_int_status
      tags: ['verify']

    - name: Display OSPF interface summary
      debug:
        var: ospf_int_status.stdout_lines
      tags: ['verify']
```

### playbooks/verify_ospf.yml

```yaml
---
- name: Comprehensive OSPF Verification
  hosts: routers
  gather_facts: no

  tasks:
    - name: Check OSPF process status
      cisco.ios.ios_command:
        commands:
          - show ip ospf
      register: ospf_process

    - name: Display OSPF process info
      debug:
        msg: "{{ ospf_process.stdout_lines[0] }}"

    - name: Check OSPF neighbors
      cisco.ios.ios_command:
        commands:
          - show ip ospf neighbor
      register: ospf_neighbors

    - name: Verify neighbor states (should be FULL)
      assert:
        that:
          - "'FULL' in ospf_neighbors.stdout[0]"
        fail_msg: "WARNING: OSPF neighbors not in FULL state on {{ inventory_hostname }}"
        success_msg: "✓ OSPF neighbors are FULL on {{ inventory_hostname }}"
      ignore_errors: yes

    - name: Display neighbor details
      debug:
        msg: "{{ ospf_neighbors.stdout_lines[0] }}"

    - name: Check routing table
      cisco.ios.ios_command:
        commands:
          - show ip route ospf
      register: ospf_routes

    - name: Display OSPF routes
      debug:
        msg: "{{ ospf_routes.stdout_lines[0] }}"

    - name: Check OSPF database
      cisco.ios.ios_command:
        commands:
          - show ip ospf database
      register: ospf_db

    - name: Display OSPF database
      debug:
        msg: "{{ ospf_db.stdout_lines[0] }}"

    - name: Test connectivity to all loopbacks
      cisco.ios.ios_command:
        commands:
          - ping 3.3.3.3 source loopback0
          - ping 4.4.4.4 source loopback0
          - ping 5.5.5.5 source loopback0
          - ping 6.6.6.6 source loopback0
          - ping 7.7.7.7 source loopback0
          - ping 8.8.8.8 source loopback0
      register: connectivity_test
      ignore_errors: yes

    - name: Display connectivity results
      debug:
        msg: "{{ connectivity_test.stdout_lines }}"
```

### playbooks/rollback.yml

```yaml
---
- name: Rollback OSPF Configuration
  hosts: routers
  gather_facts: no

  tasks:
    - name: Remove OSPF configuration
      cisco.ios.ios_config:
        lines:
          - no router ospf {{ ospf_process_id }}
      notify: save config

    - name: Remove interface IP addresses (except management)
      cisco.ios.ios_config:
        lines:
          - no ip address
        parents: "interface {{ item.name }}"
      loop: "{{ interfaces }}"
      when: "'Loopback' in item.name or 'Ethernet0/0' not in item.name"

    - name: Verify OSPF removal
      cisco.ios.ios_command:
        commands:
          - show ip ospf
      register: ospf_check
      failed_when: false

    - name: Confirm OSPF removed
      debug:
        msg: "OSPF configuration removed from {{ inventory_hostname }}"

  handlers:
    - name: save config
      cisco.ios.ios_config:
        save_when: always
```

---

## Step 9: Execution & Testing

### Initial Deployment

```bash
# Test connectivity first
ansible all -m ping

# Deploy interfaces only (dry run)
ansible-playbook playbooks/deploy_ospf.yml --tags interfaces --check

# Deploy interfaces
ansible-playbook playbooks/deploy_ospf.yml --tags interfaces

# Deploy OSPF
ansible-playbook playbooks/deploy_ospf.yml --tags ospf

# Full deployment
ansible-playbook playbooks/deploy_ospf.yml
```

### Verification

```bash
# Run comprehensive verification
ansible-playbook playbooks/verify_ospf.yml

# Check specific router group
ansible-playbook playbooks/verify_ospf.yml --limit hq_routers
ansible-playbook playbooks/verify_ospf.yml --limit branch_routers

# Quick neighbor check
ansible routers -m cisco.ios.ios_command -a "commands='show ip ospf neighbor'"

# Remove Deployment
ansible-playbook playbooks/rollback.yml
```

### Manual Verification (SSH to routers)

```bash
# On R3 (ABR)
show ip ospf neighbor
# Should see: R4 and R6

show ip ospf border-routers
# Should show ABR status

show ip route ospf
# Should see O (intra-area) and O IA (inter-area) routes

# On R4 (Core)
show ip ospf neighbor
# Should see: R3 and R5

show ip route ospf
# Should see O IA routes to Area 1 networks

# On R6 (Branch)
show ip ospf neighbor
# Should see: R3 and R7

show ip route ospf
# Should see O IA routes to Area 0 networks

# Test end-to-end connectivity
ping 10.10.4.1 source loopback1  # From any router to R4's loopback
```

---

## Step 10: Expected Results

### OSPF Neighbor Relationships

| Router | Expected Neighbors | State |
|--------|-------------------|-------|
| R3 | R4 (Area 0), R6 (Area 1) | FULL/DR or FULL/BDR |
| R4 | R3 (Area 0), R5 (Area 0) | FULL/DR or FULL/BDR |
| R5 | R4 (Area 0), R8 (Area 1) | FULL/DR or FULL/BDR |
| R6 | R3 (Area 1), R7 (Area 1) | FULL/DR or FULL/BDR |
| R7 | R6 (Area 1), R8 (Area 1) | FULL/DR or FULL/BDR |
| R8 | R5 (Area 1), R7 (Area 1) | FULL/DR or FULL/BDR |

### Route Types You Should See

- **O** = OSPF intra-area routes (within same area)
- **O IA** = OSPF inter-area routes (between Area 0 and Area 1)
- **ABRs (R3, R5)** will show both O and O IA routes
- **Area 0 routers** will see O IA routes to Area 1 networks
- **Area 1 routers** will see O IA routes to Area 0 networks

---

## Troubleshooting Guide

### Issue: Neighbors not forming

```bash
# Check interface status
show ip ospf interface

# Verify network statements
show running-config | section router ospf

# Check for area mismatches
show ip ospf interface brief

# Common fix:
router ospf 1
 network 10.1.1.0 0.0.0.3 area 1  # Verify area number matches
```

### Issue: Routes missing

```bash
# Check OSPF database
show ip ospf database

# Verify ABR functionality
show ip ospf border-routers

# Check for passive interfaces blocking adjacencies
show ip ospf interface | include Passive
```

### Issue: Ansible connection failures

```bash
# Test SSH manually
ssh ansible@192.168.33.203

# Verify management IPs
ansible all -m cisco.ios.ios_command -a "commands='show ip interface brief'"

# Check ansible inventory
ansible-inventory --graph
```

---

## Advanced Configurations (Optional)

### Add OSPF Authentication

Add to `ospf.j2` template:
```jinja
 area {{ area_number }} authentication message-digest
!
{% for interface in ospf_interfaces %}
interface {{ interface }}
 ip ospf message-digest-key 1 md5 OspfP@ss123
{% endfor %}
```

### Add Route Summarization at ABRs

Add to R3 and R5 `host_vars`:
```yaml
ospf_area_ranges:
  - area: 1
    range: 10.10.6.0 255.255.252.0  # Summarize 10.10.6-9.0/24
```

Update `ospf.j2`:
```jinja
{% if ospf_area_ranges is defined %}
{% for range in ospf_area_ranges %}
 area {{ range.area }} range {{ range.range }}
{% endfor %}
{% endif %}
```

---

## Success Criteria Checklist

- [ ] All 6 routers reachable via SSH
- [ ] All OSPF neighbors in FULL state
- [ ] R3 and R5 show ABR status
- [ ] Area 0 routers see inter-area routes to Area 1
- [ ] Area 1 routers see inter-area routes to Area 0
- [ ] All loopbacks reachable from any router
- [ ] OSPF database consistent across all routers
- [ ] No flapping adjacencies (check logs)

---

You now have a **production-grade, multi-area OSPF lab** with proper segmentation! 

