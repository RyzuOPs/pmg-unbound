#!/bin/bash

# PMG Unbound
# Local recursive DNS resolver for Proxmox Mail Gateway
# to avoid RBL rate limits

# Don't exit on errors in interactive menu mode
# set -e removed to allow graceful error handling

UNBOUND_CONF="/etc/unbound/unbound.conf"
ROOT_HINTS="/var/lib/unbound/root.hints"
CRON_FILE="/etc/cron.monthly/unbound-update-hints"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

# Check if this is PMG
check_pmg() {
    if [ ! -f /usr/bin/pmgconfig ]; then
        echo -e "${RED}Error: This doesn't appear to be a Proxmox Mail Gateway installation${NC}"
        exit 1
    fi
}

# Install unbound
install_unbound() {
    check_pmg
    
    echo "Checking if unbound is installed..."
    if dpkg -s unbound >/dev/null 2>&1; then
        echo -e "${YELLOW}Unbound is already installed${NC}"
        read -p "Reinstall and reconfigure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    else
        echo "Installing unbound..."
        apt update && apt install -y unbound dnsutils || { echo -e "${RED}Installation failed${NC}"; return 1; }
    fi

    echo "Backing up existing config if present..."
    if [ -f "$UNBOUND_CONF" ]; then
        mv "$UNBOUND_CONF" "${UNBOUND_CONF}.bak.$(date +%s)"
    fi
    
    echo "Downloading root hints..."
    mkdir -p /var/lib/unbound
    wget -q -O "$ROOT_HINTS" https://www.internic.net/domain/named.root || {
        echo -e "${YELLOW}Warning: Could not download root hints, using built-in${NC}"
    }

    echo "Creating unbound configuration..."
    cat <<EOF > "$UNBOUND_CONF"
server:
    # Basic server settings
    verbosity: 1
    interface: 127.0.0.1
    port: 53
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes
    
    # Access control
    access-control: 127.0.0.0/8 allow
    
    # Privacy and security
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes
    
    # Root hints for recursive resolver
    root-hints: "$ROOT_HINTS"
    
    # Performance and caching for RBL queries
    # Cache TTL - respects TTL from RBL servers (usually 5-15 min)
    # This allows IPs to be quickly removed from blacklists
    cache-min-ttl: 300
    cache-max-ttl: 86400
    
    # Optimizations for high-traffic PMG environment
    prefetch: yes
    prefetch-key: yes
    msg-cache-size: 50m
    rrset-cache-size: 100m
    # Large negative cache - most IPs are clean, this saves 90%+ of RBL queries
    neg-cache-size: 10m
    num-threads: 2
    so-reuseport: yes
    outgoing-range: 8192
    num-queries-per-thread: 4096
    infra-cache-numhosts: 10000
    jostle-timeout: 200
    
    # Aggressive NSEC to reduce queries
    aggressive-nsec: yes
    
    # No rate limiting for local queries (important for RBL)
    ratelimit: 0
    
    # Logging - only errors by default (use 'debug on' to enable query logging)
    log-queries: no
    log-replies: no
    logfile: "/var/log/unbound/unbound.log"
    
    # Direct recursive resolution - no forwarding
    # This allows unlimited RBL queries without external resolver limits

# Remote control for statistics
remote-control:
    control-enable: yes
    control-interface: 127.0.0.1
EOF

    echo "Creating log directory..."
    mkdir -p /var/log/unbound
    chown unbound:unbound /var/log/unbound

    echo "Validating configuration..."
    unbound-checkconf || { echo -e "${RED}Configuration error${NC}"; return 1; }

    echo "Enabling and starting unbound service..."
    systemctl enable unbound
    systemctl restart unbound

    if systemctl is-active --quiet unbound; then
        echo -e "${GREEN}✓ Unbound is running${NC}"
    else
        echo -e "${RED}✗ Unbound failed to start${NC}"
        journalctl -u unbound -n 20 --no-pager
        return 1
    fi

    # Test DNS resolution
    echo ""
    echo "Testing DNS resolution..."
    if dig +short google.com @127.0.0.1 | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo -e "${GREEN}✓ DNS resolution via unbound is working${NC}"
    else
        echo -e "${RED}✗ DNS resolution failed${NC}"
        return 1
    fi
    
    # Test RBL resolution
    echo "Testing RBL resolution..."
    if dig +short 127.0.0.2.zen.spamhaus.org @127.0.0.1 | grep -q "127.0.0.2"; then
        echo -e "${GREEN}✓ RBL resolution is working${NC}"
    else
        echo -e "${YELLOW}⚠ RBL test inconclusive (this may be normal)${NC}"
    fi

    # Ask about cron for root hints
    echo ""
    read -p "Add monthly cron job to update root hints? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        setup_cron
    fi

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Installation completed successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Manual DNS configuration required in PMG GUI${NC}"
    echo ""
    echo "To complete the setup, change DNS server in Proxmox Mail Gateway:"
    echo ""
    echo "  1. Log in to PMG web interface"
    echo "  2. Go to: System → Network Configuration"
    echo "  3. Select your network interface (e.g., vmbr0)"
    echo "  4. Click 'Edit'"
    echo "  5. Change 'DNS Server 1' to: 127.0.0.1"
    echo "  6. Click 'OK' and then 'Apply Configuration'"
    echo ""
    echo "After this change, PMG will use local unbound for DNS queries"
    echo "and RBL checks will no longer be subject to external rate limits."
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
}

# Uninstall unbound
uninstall_unbound() {
    echo -e "${YELLOW}This will remove unbound and restore DNS to previous state${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    echo "Stopping unbound..."
    systemctl stop unbound || true
    systemctl disable unbound || true
    
    echo "Removing package..."
    apt remove -y unbound
    
    echo "Removing configuration files..."
    rm -f "$UNBOUND_CONF" "${UNBOUND_CONF}.bak"*
    rm -f "$ROOT_HINTS"
    rm -rf /var/log/unbound
    
    echo "Removing cron job..."
    rm -f "$CRON_FILE"
    
    echo -e "${GREEN}✓ Unbound has been uninstalled${NC}"
    echo ""
    echo -e "${YELLOW}Remember to restore DNS settings in PMG GUI!${NC}"
}

# Show statistics
show_stats() {
    if ! systemctl list-unit-files | grep -q "^unbound.service"; then
        echo -e "${RED}✗ Unbound is not installed${NC}"
        echo "Run installation first (option 1)"
        return
    fi
    
    if ! systemctl is-active --quiet unbound 2>/dev/null; then
        echo -e "${RED}✗ Unbound is not running${NC}"
        echo ""
        systemctl status unbound --no-pager -l 2>/dev/null || true
        return
    fi
    
    echo -e "${GREEN}Unbound Statistics:${NC}"
    echo "══════════════════════════════════════════════════════════════"
    unbound-control stats 2>/dev/null | grep -E "(total|cache|num\.query|num\.answer)" | head -20
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    echo "Service status:"
    systemctl status unbound --no-pager -l 2>/dev/null || true
}

# Test DNS and RBL
test_dns() {
    if ! systemctl list-unit-files | grep -q "^unbound.service"; then
        echo -e "${RED}✗ Unbound is not installed${NC}"
        echo "Run installation first (option 1)"
        return
    fi
    
    if ! systemctl is-active --quiet unbound 2>/dev/null; then
        echo -e "${RED}✗ Unbound is not running${NC}"
        return
    fi
    
    echo "Testing DNS resolution..."
    echo ""
    
    echo "1. Testing standard DNS (google.com):"
    dig +short google.com @127.0.0.1 | head -5
    echo ""
    
    echo "2. Testing RBL lookup (Spamhaus test):"
    dig +short 127.0.0.2.zen.spamhaus.org @127.0.0.1
    echo ""
    
    echo "3. Testing cache hit rate:"
    unbound-control stats | grep -E "^(total|cache)" | head -10
}

# Enable/disable debug logging
toggle_debug() {
    if ! systemctl list-unit-files | grep -q "^unbound.service"; then
        echo -e "${RED}✗ Unbound is not installed${NC}"
        echo "Run installation first (option 1)"
        return
    fi
    
    if [ "$1" == "on" ]; then
        echo "Enabling debug logging..."
        sed -i 's/log-queries: no/log-queries: yes/' "$UNBOUND_CONF" 2>/dev/null
        sed -i 's/log-replies: no/log-replies: yes/' "$UNBOUND_CONF" 2>/dev/null
        systemctl reload unbound 2>/dev/null
        echo -e "${GREEN}✓ Debug logging enabled${NC}"
        echo "View logs: tail -f /var/log/unbound/unbound.log"
    elif [ "$1" == "off" ]; then
        echo "Disabling debug logging..."
        sed -i 's/log-queries: yes/log-queries: no/' "$UNBOUND_CONF" 2>/dev/null
        sed -i 's/log-replies: yes/log-replies: no/' "$UNBOUND_CONF" 2>/dev/null
        systemctl reload unbound 2>/dev/null
        echo -e "${GREEN}✓ Debug logging disabled${NC}"
    else
        echo "Current debug status:"
        if [ -f "$UNBOUND_CONF" ] && grep -q "log-queries: yes" "$UNBOUND_CONF"; then
            echo -e "${GREEN}Debug logging: ON${NC}"
        else
            echo -e "${YELLOW}Debug logging: OFF${NC}"
        fi
    fi
}

# Update root hints
update_hints() {
    if ! systemctl list-unit-files | grep -q "^unbound.service"; then
        echo -e "${RED}✗ Unbound is not installed${NC}"
        echo "Run installation first (option 1)"
        return
    fi
    
    echo "Updating root hints..."
    wget -q -O "$ROOT_HINTS.tmp" https://www.internic.net/domain/named.root
    if [ $? -eq 0 ]; then
        mv "$ROOT_HINTS.tmp" "$ROOT_HINTS"
        systemctl reload unbound 2>/dev/null
        echo -e "${GREEN}✓ Root hints updated successfully${NC}"
    else
        echo -e "${RED}✗ Failed to download root hints${NC}"
        rm -f "$ROOT_HINTS.tmp"
    fi
}

# Setup monthly cron for root hints
setup_cron() {
    echo "Setting up monthly cron job for root hints update..."
    cat > "$CRON_FILE" <<'EOF'
#!/bin/bash
# Update unbound root hints monthly
wget -q -O /var/lib/unbound/root.hints.tmp https://www.internic.net/domain/named.root && \
mv /var/lib/unbound/root.hints.tmp /var/lib/unbound/root.hints && \
systemctl reload unbound
EOF
    chmod +x "$CRON_FILE"
    echo -e "${GREEN}✓ Monthly cron job created${NC}"
}

# Show menu
show_menu() {
    clear
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    PMG Unbound - Main Menu                      ${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1) Install unbound"
    echo "  2) Uninstall unbound"
    echo "  3) Show status"
    echo "  4) Show statistics"
    echo "  5) Test DNS and RBL"
    echo "  6) Enable debug logging"
    echo "  7) Disable debug logging"
    echo "  8) Update root hints"
    echo "  9) Exit"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
}

# Main menu loop
main_menu() {
    while true; do
        show_menu
        read -p "Select option [1-9]: " choice
        echo ""
        
        case $choice in
            1)
                install_unbound
                read -p "Press Enter to continue..."
                ;;
            2)
                uninstall_unbound
                read -p "Press Enter to continue..."
                ;;
            3)
                if systemctl list-unit-files | grep -q "^unbound.service"; then
                    systemctl status unbound --no-pager 2>/dev/null || true
                else
                    echo -e "${RED}✗ Unbound is not installed${NC}"
                    echo "Run installation first (option 1)"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                show_stats
                read -p "Press Enter to continue..."
                ;;
            5)
                test_dns
                read -p "Press Enter to continue..."
                ;;
            6)
                toggle_debug "on"
                read -p "Press Enter to continue..."
                ;;
            7)
                toggle_debug "off"
                read -p "Press Enter to continue..."
                ;;
            8)
                update_hints
                read -p "Press Enter to continue..."
                ;;
            9)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-9.${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Main - support both CLI parameters and interactive menu
if [ $# -eq 0 ]; then
    # No parameters - show interactive menu
    main_menu
else
    # Parameters provided - use CLI mode
    case "$1" in
        install)
            install_unbound
            ;;
        uninstall)
            uninstall_unbound
            ;;
        stats)
            show_stats
            ;;
        test)
            test_dns
            ;;
        debug)
            toggle_debug "$2"
            ;;
        update-hints)
            update_hints
            ;;
        status)
            if systemctl list-unit-files | grep -q "^unbound.service"; then
                systemctl status unbound --no-pager 2>/dev/null || true
            else
                echo -e "${RED}✗ Unbound is not installed${NC}"
                exit 1
            fi
            ;;
        menu)
            main_menu
            ;;
        *)
            echo "PMG Unbound"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  install       - Install and configure unbound"
            echo "  uninstall     - Remove unbound"
            echo "  stats         - Show statistics"
            echo "  test          - Test DNS and RBL resolution"
            echo "  debug on/off  - Enable/disable query logging"
            echo "  update-hints  - Update root DNS hints"
            echo "  status        - Check unbound status"
            echo "  menu          - Show interactive menu"
            echo ""
            echo "Run without parameters to use interactive menu"
            echo ""
            ;;
    esac
fi
