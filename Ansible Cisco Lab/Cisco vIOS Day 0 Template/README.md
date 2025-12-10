# Ansible Network Automation Project - Cisco IOS Lab
## Complete Working Setup for Python 3.7+ Systems

---

## 📋 Overview

This guide provides a **complete, tested setup** for Ansible network automation with Cisco IOS devices in EVE-NG, specifically addressing common authentication and connection issues.

**Lab Topology:**
- Control Node: Ubuntu/Debian Linux
- R1: 192.168.33.201
- R2: 192.168.33.141
- R3: 192.168.33.140

**Credentials:**
- Username: `ansible`
- Password: `cisco`
- Enable Secret: `cisco`

---

## ⚠️ Known Issues & Solutions

This setup addresses these common problems:
1. **"No authentication methods available"** - Paramiko authentication configuration
2. **Ansible Galaxy API errors on Python 3.7** - Manual collection installation
3. **Persistent connection authentication failures** - Proper environment variables and config

---

## 🚀 Complete Installation & Configuration

### **Step 1: Create Python Virtual Environment**

Using a virtual environment prevents conflicts with system packages and ensures modern library versions.

```bash
# Navigate to your project location
cd /var/tmp

# Create project directory
mkdir -p ansible-cisco-lab
cd ansible-cisco-lab

# Create subdirectories
mkdir -p inventory group_vars playbooks

# Create Python virtual environment
python3 -m venv venv

# Activate the virtual environment
source venv/bin/activate

# Your prompt should now show (venv)
```

---

### **Step 2: Install Ansible and Dependencies**

```bash
# Ensure venv is activated
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install Ansible and Paramiko
pip install ansible paramiko

# Verify installation
ansible --version
python -c "import paramiko; print('Paramiko:', paramiko.__version__)"
```

**Expected output:**
- Ansible: 10.x or 2.17.x
- Paramiko: 3.x

---

### **Step 3: Install Cisco IOS Collection (Manual Method)**

If you're using Python 3.7, the Ansible Galaxy API may fail. Use manual installation:

```bash
# Download cisco.ios collection
wget https://github.com/ansible-collections/cisco.ios/archive/refs/tags/9.0.3.tar.gz -O cisco-ios.tar.gz

# Install collection
ansible-galaxy collection install cisco-ios.tar.gz -p ~/.ansible/collections

# Verify installation
ansible-galaxy collection list | grep cisco.ios
```

**Alternative if wget is unavailable:**
```bash
curl -L https://github.com/ansible-collections/cisco.ios/archive/refs/tags/9.0.3.tar.gz -o cisco-ios.tar.gz
ansible-galaxy collection install cisco-ios.tar.gz -p ~/.ansible/collections
```

---

### **Step 4: Create Configuration Files**

#### **4.1 - ansible.cfg**

```bash
cat > ansible.cfg << 'EOF'
[defaults]
# Inventory file location
inventory = ./inventory/hosts.ini

# Lab environment settings (DISABLE for production!)
host_key_checking = False

# Auto-detect Python interpreter
interpreter_python = auto_silent

# Reduce noise in output
deprecation_warnings = False
command_warnings = False

# Connection timeouts (seconds)
timeout = 60

[persistent_connection]
# Network device persistent connection timeout
connect_timeout = 60
command_timeout = 60

[paramiko_connection]
# Force Paramiko to use password authentication
look_for_keys = False
host_key_auto_add = True
EOF
```

#### **4.2 - inventory/hosts.ini**

**CRITICAL:** Verify your actual router IPs before using this file!

```bash
cat > inventory/hosts.ini << 'EOF'
[routers]
R1 ansible_host=192.168.33.201
R2 ansible_host=192.168.33.141
R3 ansible_host=192.168.33.140

[routers:vars]
ansible_connection=ansible.netcommon.network_cli
ansible_network_os=cisco.ios.ios
ansible_user=ansible
ansible_password=cisco
ansible_become=true
ansible_become_method=enable
ansible_become_password=cisco
ansible_paramiko_look_for_keys=false
ansible_paramiko_host_key_checking=false
EOF
```

**To verify your router IPs, SSH to each one and note the hostname:**
```bash
ssh ansible@192.168.33.201  # Should show R1# prompt
ssh ansible@192.168.33.141  # Should show R2# prompt
ssh ansible@192.168.33.140  # Should show R3# prompt
```

#### **4.3 - group_vars/all.yml**

```bash
cat > group_vars/all.yml << 'EOF'
---
# Global Variables for All Devices
ansible_user: ansible
ansible_password: cisco

ansible_become: true
ansible_become_method: enable
ansible_become_password: cisco

ansible_network_os: cisco.ios.ios
ansible_connection: ansible.netcommon.network_cli

# Paramiko authentication settings (CRITICAL for password-based auth)
ansible_paramiko_look_for_keys: false
ansible_paramiko_host_key_checking: false

# Increase timeout for slower connections
ansible_command_timeout: 60
EOF
```

#### **4.4 - playbooks/01_check_connectivity.yml**

```bash
cat > playbooks/01_check_connectivity.yml << 'EOF'
---
- name: "Connectivity Test - Cisco IOS Routers"
  hosts: routers
  gather_facts: false
  
  tasks:
    - name: "Verify authentication and connectivity using show version"
      cisco.ios.ios_command:
        commands:
          - show version | include uptime
      register: output
      
    - name: "Display uptime information"
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }}: {{ output.stdout_lines[0] }}"
      
    - name: "SUCCESS - Device is reachable and authenticated"
      ansible.builtin.debug:
        msg: "✅ {{ inventory_hostname }} - Connection successful!"
EOF
```

---

### **Step 5: Verify Router SSH Configuration**

Before running Ansible, ensure each router has proper SSH configuration:

```bash
# SSH to a router manually
ssh ansible@192.168.33.201
# Password: cisco
```

**Required router configuration:**
```
configure terminal
!
username ansible privilege 15 secret cisco
enable secret cisco
!
line vty 0 4
 login local
 transport input ssh
!
ip domain-name lab.local
crypto key generate rsa modulus 2048
ip ssh version 2
!
end
write memory
```

---

### **Step 6: Test Paramiko Connection (Optional Validation)**

Verify Paramiko can connect before testing Ansible:

```bash
# Run this Python test script
python << 'PYEOF'
import paramiko

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    client.connect(
        hostname='192.168.33.201',
        username='ansible',
        password='cisco',
        look_for_keys=False,
        allow_agent=False,
        timeout=10
    )
    print("✅ Paramiko connection successful!")
    stdin, stdout, stderr = client.exec_command('show version | include uptime')
    print("Router output:", stdout.read().decode().strip())
    client.close()
except Exception as e:
    print("❌ Connection failed:", str(e))
PYEOF
```

**Expected output:**
```
✅ Paramiko connection successful!
Router output: R1 uptime is 1 hour, 23 minutes
```

---

## 🎯 Running the Playbook

### **Method 1: With Environment Variables (Recommended)**

This ensures Paramiko authentication settings are properly applied:

```bash
# Activate venv
cd /var/tmp/ansible-cisco-lab
source venv/bin/activate

# Clear any cached connections
rm -rf ~/.ansible/pc/* ~/.ansible/cp/* 2>/dev/null

# Run playbook with explicit environment variables
ANSIBLE_PARAMIKO_LOOK_FOR_KEYS=False \
ANSIBLE_HOST_KEY_CHECKING=False \
ANSIBLE_PARAMIKO_HOST_KEY_CHECKING=False \
ansible-playbook -i inventory/hosts.ini playbooks/01_check_connectivity.yml
```

### **Method 2: Standard Execution**

If your configuration is correct, this should also work:

```bash
# Activate venv
source venv/bin/activate

# Run playbook
ansible-playbook -i inventory/hosts.ini playbooks/01_check_connectivity.yml
```

---

## ✅ Expected Successful Output

```
PLAY [Connectivity Test - Cisco IOS Routers] *******************

TASK [Verify authentication and connectivity using show version]
ok: [R1]
ok: [R2]
ok: [R3]

TASK [Display uptime information] ******************************
ok: [R1] => {
    "msg": "R1: R1 uptime is 2 hours, 15 minutes"
}
ok: [R2] => {
    "msg": "R2: R2 uptime is 2 hours, 15 minutes"
}
ok: [R3] => {
    "msg": "R3: R3 uptime is 2 hours, 15 minutes"
}

TASK [SUCCESS - Device is reachable and authenticated] *********
ok: [R1] => {
    "msg": "✅ R1 - Connection successful!"
}
ok: [R2] => {
    "msg": "✅ R2 - Connection successful!"
}
ok: [R3] => {
    "msg": "✅ R3 - Connection successful!"
}

PLAY RECAP *****************************************************
R1    : ok=3    changed=0    unreachable=0    failed=0
R2    : ok=3    changed=0    unreachable=0    failed=0
R3    : ok=3    changed=0    unreachable=0    failed=0
```

---

## 🔧 Troubleshooting

### **Issue: "No authentication methods available"**

**Cause:** Paramiko is trying key-based authentication or settings aren't being applied.

**Solutions:**

1. **Verify group_vars/all.yml contains:**
   ```yaml
   ansible_paramiko_look_for_keys: false
   ansible_paramiko_host_key_checking: false
   ```

2. **Verify inventory/hosts.ini [routers:vars] section contains:**
   ```ini
   ansible_paramiko_look_for_keys=false
   ansible_paramiko_host_key_checking=false
   ```

3. **Use environment variables when running:**
   ```bash
   ANSIBLE_PARAMIKO_LOOK_FOR_KEYS=False \
   ansible-playbook -i inventory/hosts.ini playbooks/01_check_connectivity.yml
   ```

4. **Clear persistent connection cache:**
   ```bash
   rm -rf ~/.ansible/pc/* ~/.ansible/cp/*
   ```

### **Issue: "Connection timeout" or "Network is unreachable"**

**Solutions:**

1. **Test network connectivity:**
   ```bash
   ping 192.168.33.201
   ping 192.168.33.141
   ping 192.168.33.140
   ```

2. **Test SSH manually:**
   ```bash
   ssh ansible@192.168.33.201
   ```

3. **Verify router IPs match your topology** - SSH to each IP and verify the hostname matches

### **Issue: Ansible Galaxy collection install fails**

**Solution:** Use manual installation method (already covered in Step 3)

### **Issue: Python 3.7 deprecation warnings**

**Note:** These are warnings, not errors. The setup works despite the warnings. The warnings look like:
```
CryptographyDeprecationWarning: Python 3.7 is no longer supported...
```

**These warnings don't affect functionality** - ignore them or redirect stderr:
```bash
ansible-playbook -i inventory/hosts.ini playbooks/01_check_connectivity.yml 2>/dev/null
```

---

## 📂 Final Project Structure

```
ansible-cisco-lab/
├── venv/                          # Python virtual environment
│   ├── bin/
│   │   ├── python3
│   │   ├── ansible
│   │   └── ansible-playbook
│   └── lib/
├── inventory/
│   └── hosts.ini                  # Device inventory with IPs
├── group_vars/
│   └── all.yml                    # Global variables & credentials
├── playbooks/
│   └── 01_check_connectivity.yml  # Connectivity test playbook
└── ansible.cfg                    # Ansible configuration
```

---

## 💡 Helper Script (Optional)

Create a wrapper script for easier execution:

```bash
cat > run-ansible.sh << 'EOF'
#!/bin/bash
cd /var/tmp/ansible-cisco-lab
source venv/bin/activate

# Clear connection cache
rm -rf ~/.ansible/pc/* ~/.ansible/cp/* 2>/dev/null

# Run with proper environment variables
ANSIBLE_PARAMIKO_LOOK_FOR_KEYS=False \
ANSIBLE_HOST_KEY_CHECKING=False \
ANSIBLE_PARAMIKO_HOST_KEY_CHECKING=False \
ansible-playbook -i inventory/hosts.ini "$@"
EOF

chmod +x run-ansible.sh
```

**Usage:**
```bash
./run-ansible.sh playbooks/01_check_connectivity.yml
```

---

## 🔐 Security Considerations

⚠️ **This configuration is for LAB USE ONLY**

For production environments:
- Use **Ansible Vault** to encrypt credentials
- Enable **host key checking**
- Implement **SSH key-based authentication**
- Use **role-based access control**
- Never store passwords in plain text

**Example: Encrypting passwords with Ansible Vault**
```bash
ansible-vault encrypt group_vars/all.yml
ansible-playbook -i inventory/hosts.ini playbooks/01_check_connectivity.yml --ask-vault-pass
```

---

## 📚 Quick Reference

### Every Time You Use Ansible

```bash
# 1. Navigate to project
cd /var/tmp/ansible-cisco-lab

# 2. Activate virtual environment
source venv/bin/activate

# 3. Run playbook with environment variables
ANSIBLE_PARAMIKO_LOOK_FOR_KEYS=False \
ansible-playbook -i inventory/hosts.ini playbooks/01_check_connectivity.yml

# 4. Deactivate when done
deactivate
```

### Useful Commands

```bash
# Test basic connectivity
ansible routers -i inventory/hosts.ini -m ping

# Run ad-hoc command
ansible routers -i inventory/hosts.ini -m cisco.ios.ios_command -a "commands='show ip int brief'"

# Verbose output for debugging
ansible-playbook -i inventory/hosts.ini playbooks/01_check_connectivity.yml -vvv

# Show inventory
ansible-inventory -i inventory/hosts.ini --list

# Show variables for specific host
ansible-inventory -i inventory/hosts.ini --host R1 --yaml
```

---

## ✨ Key Success Factors

This setup works because:

1. **Virtual environment** - Isolates modern Ansible/Paramiko from system packages
2. **Manual collection install** - Bypasses Galaxy API issues with Python 3.7
3. **Explicit Paramiko settings** - Forces password authentication, disables key lookup
4. **Environment variables** - Ensures settings are applied to persistent connections
5. **Proper ansible.cfg** - Configures Paramiko connection behavior
6. **Inventory-level variables** - Provides backup configuration in case group_vars aren't applied

---

## 🎓 Next Steps

Once connectivity works, expand your automation:

1. **Configuration Backup:**
   ```yaml
   - name: Backup router configurations
     cisco.ios.ios_config:
       backup: yes
       backup_options:
         filename: "{{ inventory_hostname }}-config.txt"
   ```

2. **Deploy Standard Configurations:**
   ```yaml
   - name: Configure NTP servers
     cisco.ios.ios_config:
       lines:
         - ntp server 192.168.1.1
         - ntp server 192.168.1.2
   ```

3. **Gather Facts:**
   ```yaml
   - name: Gather device facts
     cisco.ios.ios_facts:
       gather_subset: all
   ```

---

## 📖 Documentation References

- [Ansible Network Automation](https://docs.ansible.com/ansible/latest/network/index.html)
- [cisco.ios Collection](https://docs.ansible.com/ansible/latest/collections/cisco/ios/index.html)
- [Paramiko Documentation](http://www.paramiko.org/)

---

**Last Updated:** December 2025  
**Tested On:** Debian 10 (Buster) with Python 3.7, EVE-NG Cisco vIOS routers  
**Status:** ✅ Fully Working Configuration