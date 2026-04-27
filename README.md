# PMG Unbound

**Local recursive DNS resolver for Proxmox Mail Gateway**

Script to install and manage Unbound DNS server on PMG to avoid query rate limits when checking IP addresses against RBL (Realtime Blackhole Lists).

## 🎯 Problem

Proxmox Mail Gateway checks every incoming email against multiple RBL lists (e.g., Spamhaus, SORBS, SpamCop). Direct queries to public DNS servers quickly exhaust rate limits, causing:
- Mail processing delays
- DNS timeout errors
- Potential server IP blocks

## ✅ Solution

Unbound as a local recursive resolver:
- **Direct queries** to authoritative DNS servers (no intermediaries)
- **No rate limits** on RBL queries
- **Smart caching** - optimized for RBL
- **High performance** - faster DNS responses

## 📦 Installation

### 1. Download the script
```bash
wget https://raw.githubusercontent.com/RyzuOPs/pmg-unbound/main/pmg-unbound.sh
chmod +x pmg-unbound.sh
```

### 2. Install Unbound
```bash
./pmg-unbound.sh install
```

During installation, you'll be asked whether to add a monthly cron job for root hints updates (recommended: YES).

### 3. Configure DNS in PMG

⚠️ **IMPORTANT:** After installation, you must manually change DNS in the GUI:

1. Log in to PMG web interface
2. Go to: **System → Network Configuration**
3. Select your network interface (e.g., vmbr0)
4. Click **Edit**
5. Change **DNS Server 1** to: `127.0.0.1`
6. Click **OK** and **Apply Configuration**

## 🚀 Usage

### Interactive Menu (Recommended)

Simply run the script without parameters to access the interactive menu:

```bash
./pmg-unbound.sh
```

You'll see a menu like this:
```
════════════════════════════════════════════════════════════════
                    PMG Unbound - Main Menu
════════════════════════════════════════════════════════════════

  1) Install unbound
  2) Uninstall unbound
  3) Show status
  4) Show statistics
  5) Test DNS and RBL
  6) Enable debug logging
  7) Disable debug logging
  8) Update root hints
  9) Exit

════════════════════════════════════════════════════════════════
Select option [1-9]:
```

### Command Line Mode (Optional)

You can also use command line parameters for scripting or automation:

```bash
# Installation
./pmg-unbound.sh install

# Service status
./pmg-unbound.sh status

# Statistics (cache hits, queries)
./pmg-unbound.sh stats

# Test DNS and RBL
./pmg-unbound.sh test

# Uninstall
./pmg-unbound.sh uninstall

# Enable/disable debug logging
./pmg-unbound.sh debug on
./pmg-unbound.sh debug off

# Update root DNS hints
./pmg-unbound.sh update-hints

# Show interactive menu
./pmg-unbound.sh menu
```

## 📋 Typical Workflow

### After first installation:
```bash
# 1. Run the script
./pmg-unbound.sh

# 2. Select option 1 (Install unbound)
# Answer 'Y' to cron question

# 3. Select option 5 (Test DNS and RBL)
# Verify everything works

# 4. Select option 3 (Show status)
# Check that unbound is running

# 5. Change DNS in PMG GUI to 127.0.0.1 (System → Network Configuration)

# 6. Select option 9 (Exit)
```

### Using CLI Mode:
```bash
# Quick installation with CLI parameters
./pmg-unbound.sh install
# Answer 'Y' to cron question

# Test functionality
./pmg-unbound.sh test

# Check status
./pmg-unbound.sh status

# 4. Change DNS in PMG GUI to 127.0.0.1 (System → Network Configuration)
```

### Daily usage:

**Using Interactive Menu:**
```bash
# Run the script
./pmg-unbound.sh

# Select option 3 (Show status) - Check if everything is working
# Select option 4 (Show statistics) - View cache efficiency
# Select option 6 (Enable debug) - If you have problems
# Then view logs: tail -f /var/log/unbound/unbound.log
# Select option 7 (Disable debug) - After diagnosis
```

**Using CLI Mode:**
```bash
# Check if everything is working
./pmg-unbound.sh status

# View cache statistics (how many queries you're saving)
./pmg-unbound.sh stats

# If you have problems, enable debug
./pmg-unbound.sh debug on
tail -f /var/log/unbound/unbound.log
# ... diagnosis ...
./pmg-unbound.sh debug off
```

### Troubleshooting:

**Using Interactive Menu:**
```bash
# Run the script
./pmg-unbound.sh

# 1. Select option 3 (Show status)
# 2. Select option 5 (Test DNS and RBL)
# 3. Select option 6 (Enable debug logging)
# 4. View logs: tail -f /var/log/unbound/unbound.log
# 5. Check system logs: journalctl -u unbound -n 50
# 6. Select option 7 (Disable debug logging)
```

**Using CLI Mode:**
```bash
# 1. Check service status
./pmg-unbound.sh status

# 2. Test DNS resolution
./pmg-unbound.sh test

# 3. Enable detailed logs
./pmg-unbound.sh debug on

# 4. View logs in real-time
tail -f /var/log/unbound/unbound.log

# 5. Check system logs
journalctl -u unbound -n 50

# 6. After fixing, disable debug
./pmg-unbound.sh debug off
```

### Maintenance:

**Using Interactive Menu:**
```bash
./pmg-unbound.sh
# Select option 8 (Update root hints) - Monthly update
# Select option 4 (Show statistics) - Check cache efficiency
```

**Using CLI Mode:**
```bash
# Monthly root hints update (or automatically via cron)
./pmg-unbound.sh update-hints

# Check cache efficiency
./pmg-unbound.sh stats | grep cache

# Restart service (if needed)
systemctl restart unbound
```

## ⚙️ Configuration

### RBL Optimizations

The script automatically configures:

**TTL Cache:**
- `cache-min-ttl: 300` (5 min) - respects TTL from RBL servers (usually 5-15 min)
- `cache-max-ttl: 86400` (24h) - maximum TTL
- Allows IPs to be quickly removed from blacklists when their status changes

**Performance:**
- `msg-cache-size: 50m` - message cache
- `rrset-cache-size: 100m` - record cache
- `neg-cache-size: 10m` - large negative answer cache (most IPs are clean, saves 90%+ of RBL queries)
- `num-threads: 2` - multi-threading
- `so-reuseport: yes` - better query distribution
- `outgoing-range: 8192` - more ports for outgoing queries
- `infra-cache-numhosts: 10000` - larger infrastructure cache

**Security:**
- `hide-identity: yes`
- `hide-version: yes`
- `harden-glue: yes`
- `harden-dnssec-stripped: yes`

### Logging

By default, only errors are logged (`/var/log/unbound/unbound.log`).

Enable full query logging for debugging:
```bash
./pmg-unbound.sh debug on
tail -f /var/log/unbound/unbound.log
```

## 📊 Statistics

Check cache efficiency:

```bash
./pmg-unbound.sh stats
```

Example output:
```
total.num.queries=123456
total.cache.hits=98765
total.recursion.time.avg=0.123456
```

Cache hit ratio > 80% = excellent optimization! 🎉

## 🔧 Maintenance

### Automatic root hints updates

If you enabled cron during installation, root hints will be updated automatically every month.

Manual update:
```bash
./pmg-unbound.sh update-hints
```

### Monitoring

Check if Unbound is working correctly:
```bash
systemctl status unbound
./pmg-unbound.sh test
```

## 🐛 Troubleshooting

### Unbound won't start
```bash
# Check logs
journalctl -u unbound -n 50

# Validate configuration
unbound-checkconf
```

### DNS doesn't work after GUI change
```bash
# Check if DNS points to localhost
cat /etc/resolv.conf

# Restart unbound and PMG
systemctl restart unbound
systemctl restart pmgproxy pmgdaemon
```

### Low cache hit ratio
```bash
# Enable debug and watch queries
./pmg-unbound.sh debug on
tail -f /var/log/unbound/unbound.log

# Check if PMG is using 127.0.0.1
dig google.com @127.0.0.1
```

## 📋 Requirements

- **System:** Proxmox Mail Gateway (Debian-based)
- **Permissions:** root
- **Packages:** apt, wget, systemd (standard in PMG)

## 🔒 Security

- Unbound listens **only** on `127.0.0.1` (localhost)
- No external access
- Recursive name resolution directly to authoritative servers

## 📝 License

MIT License - use, modify, and share freely.

## 🤝 Support

Problems? Suggestions? Open an Issue on GitHub!

## 🌟 Author

Script created for Proxmox Mail Gateway optimization.

---

**Like the project? Give it a star ⭐ on GitHub!**
