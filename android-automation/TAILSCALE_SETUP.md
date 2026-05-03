# Tailscale Setup for Dashboard Access

## Overview

This guide explains how to set up Tailscale access to the media-rs test dashboard from external networks.

## Quick Setup

### 1. Install Tailscale

```bash
# On Ubuntu/Debian
curl -fsSL https://tailscale.com/install.sh | sh

# Or download manually
wget https://tailscale.com/download/linux/amd64/tailscale -O tailscale
chmod +x tailscale
sudo mv tailscale /usr/local/bin/

# Start Tailscale
sudo tailscale up

# Login when prompted (or use pre-shared key)
```

### 2. Get Your Tailscale IP

```bash
tailscale ip
# Example output: 100.x.x.x or 100.x.x.x (subnet-routed)
```

### 3. Access the Dashboard

Once Tailscale is running:

```
# Option 1: Direct access (if Tailscale is configured as a server)
http://[TAILSCALE-IP]:8080/android-tests/dashboard/comprehensive.html

# Option 2: Share Tailscale network
# 1. Get your Tailscale IP: tailscale ip
# 2. Access from any device on the same Tailscale network
# 3. Or share via Tailscale's built-in sharing features
```

### 4. Serve Dashboard Locally

```bash
cd /home/kushal/Documents/Projects/media-rs/android-automation/android-tests/dashboard
python3 -m http.server 8080

# Or use a static file server
npx serve .
```

Then access from any device on the Tailscale network:
```
http://[LOCAL-IP]:8080/
```

## External Access Options

### Option 1: Tailscale Wireguard Server

1. **Set up Tailscale as a Wireguard server**
   - Configure Tailscale to accept incoming connections
   - Port forwarding in Tailscale admin console
   
2. **Access from anywhere**
   - Use Tailscale's any-cast features
   - Or set up a specific Wireguard tunnel

### Option 2: Tailscale + Public IP

```bash
# Set up port forwarding in Tailscale admin console
# Then access via your public IP
http://your-public-ip:8080/android-tests/dashboard/comprehensive.html
```

### Option 3: Tailscale + nginx/Apache

```bash
# Install nginx
sudo apt install nginx

# Create configuration
sudo nano /etc/nginx/sites-available/media-rs-dashboard

# Content:
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

# Enable site
sudo ln -s /etc/nginx/sites-available/media-rs-dashboard /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Then configure Tailscale to forward port 80.

## Troubleshooting

### Issue: Dashboard not accessible

```bash
# Check Tailscale status
tailscale status

# Check if port is listening
sudo lsof -i :8080

# Check firewall rules
sudo ufw status
sudo ufw allow 8080/tcp

# Restart services
sudo systemctl restart tailscale
sudo systemctl restart nginx
```

### Issue: Permission denied

```bash
# Ensure dashboard is readable
chmod 755 /home/kushal/Documents/Projects/media-rs/android-automation/android-tests/dashboard
chmod 644 /home/kushal/Documents/Projects/media-rs/android-automation/android-tests/dashboard/*.html
```

## Security Considerations

1. **Use Tailscale's built-in authentication**
   - Don't expose dashboard directly to the internet
   - Use Tailscale's identity-based access control

2. **Limit access**
   - Restrict to specific Tailscale users/groups
   - Use Tailscale's ACLs

3. **HTTPS**
   - Consider using Let's Encrypt with Tailscale
   - Or use a reverse proxy with TLS

4. **Regular updates**
   - Keep Tailscale updated: sudo tailscale up --fix

## Quick Commands

```bash
# Start Tailscale
sudo tailscale up

# Get your IP
tailscale ip

# View peers
tailscale peers

# Share with specific user
tailscale share [USER-ID]

# Fix connectivity issues
tailscale up --fix

# View logs
journalctl -u tailscale -f

# Restart Tailscale
sudo systemctl restart tailscale
```

## Alternative: SSH Tunnel

If Tailscale direct access isn't working, use SSH tunnel:

```bash
# From remote machine
ssh -L 8080:localhost:8080 kushal@[TAILSCALE-IP]

# Then access: http://localhost:8080
```

## Summary

- **Tailscale IP**: Use `tailscale ip` to get your address
- **Dashboard URL**: `http://[TAILSCALE-IP]:8080/android-tests/dashboard/comprehensive.html`
- **Local access**: `python3 -m http.server 8080`
- **External access**: Configure Tailscale port forwarding or use SSH tunnel

For production use, consider:
1. Setting up proper authentication
2. Using HTTPS/TLS
3. Rate limiting and security headers
4. Regular backups of test data

---

**Last Updated**: Mon 2026-04-20  
**Status**: ✅ Ready for Tailscale deployment
