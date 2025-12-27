# Cisco OSPF Network Automation - Copilot Instructions

This repository contains Ansible-based automation for deploying OSPF (Open Shortest Path First) dynamic routing configurations on Cisco routers in lab environments. All projects target Cisco IOS devices (vIOS, IOSv) managed via SSH.

## Architecture Overview

### Multi-Project Structure
- **3-Router OSPF Design** (`ospf-lab/`): Simple 3-router topology with 2 OSPF areas
- **multi-site-ospf/**: Production-grade 6-router setup with phased deployments
- **ospf-lab-6r/**: Advanced 6-router lab with HQ/Branch structure and ABR (Area Border Router) roles
- **Cisco vIOS Day 0 Template**: Base connectivity verification template

### Data Flow Pattern
1. **Inventory Layer** (`inventory/hosts.yml`): Defines router groups (hq_routers, branch_routers, routers)
2. **Variable Layer** (`inventory/group_vars/`, `host_vars/`): Stores interface and OSPF configs per router/group
3. **Role Layer** (`roles/`): Two core roles - `base_interfaces` (layer 3 setup) and `ospf` (routing config)
4. **Template Layer** (Jinja2): Generates actual IOS CLI commands from variables
5. **Execution Layer** (`playbooks/`): Orchestrates roles with handlers and validation tasks

### Critical Design Decision: Host Vars Drive Configuration
Configuration is entirely **variable-driven**. Router-specific host vars define IP addresses, interface names, and OSPF parameters. Templates render these into CLI commands. This allows one playbook to deploy across different topologies by changing only inventory/vars files.

## Key Development Patterns

### 1. Interface Configuration Pattern
**Location**: `roles/base_interfaces/`

```yaml
# In host_vars/R3.yml:
interfaces:
  - name: Ethernet0/1
    description: "TO_R6_BRANCH_AREA1"
    ipv4_address: 10.1.1.1
    ipv4_netmask: 255.255.255.252

# Template renders to: interface Ethernet0/1 → description → ip address
```

**Pattern**: Define interfaces as structured list in host_vars. `base_interfaces/tasks/main.yml` uses `cisco.ios.ios_config` with template source to apply all at once.

### 2. OSPF Deployment Pattern
**Location**: `roles/ospf/`

Variables define network statements as list of dicts with network, wildcard, and area. Template iterates:

```jinja
{% for network in ospf_networks %}
 network {{ network.network }} {{ network.wildcard }} area {{ network.area }}
{% endfor %}
```

**Critical**: Passive interfaces declared separately. ABR routers require network statements in BOTH areas they connect.

### 3. Phased Deployment Pattern
**Location**: `multi-site-ospf/` and `ospf-lab-6r/`

- `phase1_deploy.yml`: Deploys base_interfaces + OSPF on all routers simultaneously
- `phase2_abr_deploy.yml` (in multi-site-ospf): Optional second phase for ABR tuning
- `verify_ospf.yml`: Runs show commands to verify neighbors, routes, database

**Pattern**: Use handlers with `notify: save config` to persist configs only when changes occur. Include extensive `ios_command` tasks with `retries` to wait for OSPF convergence (typically 15-30 seconds).

### 4. Inventory Grouping Pattern
- **hq_routers**: Core routers in Area 0 (R3, R4, R5 in ospf-lab-6r)
- **branch_routers**: Edge routers in Area 1 (R6, R7, R8)
- **routers**: Combines both for single-playbook deployment

Use `ansible_host` for management IP (e.g., 192.168.33.x). This is separate from data plane IPs defined in interfaces.

## Configuration and Execution

### Ansible Config (`ansible.cfg`)
- Connection type: Implicit (defaults to ssh for Cisco IOS)
- `gathering = explicit`: Only gather facts when explicitly requested to save time
- `timeout = 60`, `connect_timeout = 60`: Necessary for initial router connections
- `host_key_checking = False`: Lab environment bypass

### Running Playbooks

```bash
# Deploy all OSPF config (both interface and routing)
ansible-playbook playbooks/deploy_ospf.yml

# Deploy only interfaces (for debugging)
ansible-playbook playbooks/deploy_ospf.yml --tags interfaces

# Deploy only OSPF config
ansible-playbook playbooks/deploy_ospf.yml --tags ospf

# Verify after deployment
ansible-playbook playbooks/verify_ospf.yml
```

### Rollback (ospf-lab-6r only)
```bash
ansible-playbook playbooks/rollback.yml
```

## Common Patterns to Reuse

### Waiting for Convergence
Always include 15-30 second pause after OSPF config and use `retries/until` on show commands:

```yaml
- name: Wait for OSPF to converge
  pause:
    seconds: 15
    prompt: "Waiting for OSPF adjacencies to form..."

- name: Verify OSPF neighbors
  cisco.ios.ios_command:
    commands: ["show ip ospf neighbor"]
  register: ospf_neighbors
  retries: 3
  delay: 5
  until: ospf_neighbors is succeeded
```

### Template-Based Bulk Config
Use `ios_config` with `src:` parameter pointing to Jinja2 template. This is cleaner than multiple `ios_command` tasks for complex configs:

```yaml
- name: Deploy OSPF from template
  cisco.ios.ios_config:
    src: ospf.j2
  notify: save config
```

### Gathering Specific Facts
Avoid full `ios_facts` in production playbooks (slow). Use targeted commands:

```yaml
- name: Gather device facts (minimal)
  cisco.ios.ios_facts:
    gather_subset: min
```

## File Reference Guide

### Essential Configuration Files
- `ansible.cfg`: Connection settings (all projects)
- `inventory/hosts.yml`: Router IP addresses and grouping
- `inventory/group_vars/all.yml`: Variables applied to all routers (ospf_process_id, ospf_reference_bandwidth)
- `inventory/group_vars/routers.yml`: Router group defaults
- `inventory/host_vars/R*.yml`: Per-router interfaces and OSPF networks

### Templates
- `roles/base_interfaces/templates/interfaces.j2`: Generates interface configs
- `roles/ospf/templates/ospf.j2`: Generates router ospf process config
- `roles/ospf/defaults/main.yml`: OSPF role defaults (retry counts, timeouts)

### Playbooks
- `playbooks/deploy_ospf.yml`: Main deployment (runs base_interfaces then ospf roles)
- `playbooks/verify_ospf.yml`: Post-deployment verification
- `playbooks/rollback.yml`: Config restore (ospf-lab-6r only)

## Debugging and Troubleshooting

### Connection Issues
- Verify `ansible_host` matches actual management IP in inventory
- Check `ssh` access: `ssh ansible@192.168.33.xxx` from control node
- Review ansible.cfg timeout settings if connections drop

### Template Rendering Errors
- Templates reference variables like `ospf_router_id`, `ospf_networks`. Missing these causes render failures
- Check `host_vars` for required keys in ospf_networks dicts: `network`, `wildcard`, `area`

### OSPF Not Converging
- Run `verify_ospf.yml` to see neighbor relationships
- Check that interfaces are in correct OSPF areas (network statements must match)
- Verify passive interfaces don't prevent needed adjacencies
- Ensure loopback0 addresses match ospf_router_id

### Configuration Persistence
- Handlers only save if `ios_config` task has `changed: true`
- Use `notify: save config` on all configuration tasks to ensure persistence

## Team Conventions

- All comments in configs use `!` (IOS standard), no C-style comments
- Router IDs set to loopback0 primary address (e.g., R3 = 3.3.3.3)
- Point-to-point links use /30 subnets (4 hosts, minimal waste)
- Area 0 always contains backbone/core routers, Area 1 for branches (follows OSPF best practices)
- Variable names use underscores: `ospf_router_id`, not `ospfRouterId`
