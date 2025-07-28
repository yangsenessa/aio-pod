# AIO-Pod Nginx SSL Setup

This document describes how to set up nginx with SSL certificates for the AIO-Pod service using the domain `mcp.aio2030.fun`.

## Prerequisites

1. **Domain Configuration**: Ensure your domain `mcp.aio2030.fun` is pointing to your server's IP address
2. **Root Access**: You need root privileges to install nginx and configure SSL
3. **Open Ports**: Ports 80 and 443 must be open on your server

## Quick Deployment

For a complete automated deployment, run:

```bash
sudo ./deploy.sh
```

This script will:
- Install nginx and certbot
- Configure SSL certificates with Let's Encrypt
- Set up reverse proxy for AIO-Pod services
- Install system service for auto-start
- Test the deployment

## Manual Setup

If you prefer to run the setup step by step:

### 1. Install Nginx and SSL

```bash
sudo ./setup_nginx_ssl.sh
```

This script will:
- Install nginx and certbot
- Generate SSL certificates for your domain
- Configure nginx with reverse proxy settings
- Set up automatic certificate renewal

### 2. Start AIO-Pod Services

```bash
./start_aio_pod.sh
```

This will start the AIO-Pod file server and exec server.

### 3. Install System Service (Optional)

```bash
sudo cp aio-pod.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable aio-pod.service
```

## Configuration Files

### nginx.conf
The main nginx configuration file that:
- Sets up reverse proxy for ports 8000 and 8001
- Configures SSL with Let's Encrypt certificates
- Implements security headers and rate limiting
- Handles large file uploads

### setup_nginx_ssl.sh
Automated script that:
- Installs nginx and certbot
- Obtains SSL certificates from Let's Encrypt
- Configures firewall rules
- Sets up automatic certificate renewal

### start_aio_pod.sh
Script to start AIO-Pod services:
- Activates conda environment
- Starts file server on port 8001
- Starts exec server on port 8000 (if exists)
- Waits for services to be ready

### stop_aio_pod.sh
Script to stop AIO-Pod services:
- Gracefully stops services by PID
- Cleans up log files
- Archives old logs

## Service Management

### Check Service Status
```bash
# Check nginx
sudo systemctl status nginx

# Check AIO-Pod services
systemctl status aio-pod

# Check if ports are in use
sudo lsof -i :8000
sudo lsof -i :8001
sudo lsof -i :443
```

### Start/Stop Services
```bash
# Start services
sudo systemctl start nginx
./start_aio_pod.sh

# Stop services
./stop_aio_pod.sh
sudo systemctl stop nginx

# Restart services
sudo systemctl restart nginx
systemctl restart aio-pod
```

### View Logs
```bash
# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# AIO-Pod service logs
tail -f aio_server/file_server.log
tail -f aio_server/exec_server.log

# System service logs
journalctl -u aio-pod -f
```

## SSL Certificate Management

### Certificate Location
Certificates are stored in `/etc/letsencrypt/live/mcp.aio2030.fun/`

### Manual Renewal
```bash
sudo certbot renew
sudo systemctl reload nginx
```

### Check Certificate Status
```bash
sudo certbot certificates
```

## API Endpoints

Once deployed, your API will be available at:

- **Health Check**: `https://mcp.aio2030.fun/health`
- **File Upload**: `POST https://mcp.aio2030.fun/api/v1/upload/{type}`
- **File Download**: `GET https://mcp.aio2030.fun/api/v1/?type={type}&filename={filename}`
- **MCP Execute**: `POST https://mcp.aio2030.fun/api/v1/mcp/{filename}`

## Testing

### Test HTTPS
```bash
curl -k https://mcp.aio2030.fun/health
```

### Test SSL Certificate
```bash
openssl s_client -connect mcp.aio2030.fun:443 -servername mcp.aio2030.fun
```

### Test File Upload
```bash
curl -X POST -F "file=@test.txt" https://mcp.aio2030.fun/api/v1/upload/mcp
```

## Troubleshooting

### Common Issues

1. **Certificate Not Obtained**
   - Ensure domain DNS is pointing to server IP
   - Check that ports 80 and 443 are open
   - Verify domain is accessible from internet

2. **Nginx Configuration Error**
   ```bash
   sudo nginx -t
   ```

3. **Services Not Starting**
   - Check conda environment: `conda activate aiopod`
   - Check Python dependencies: `pip install -r requirements.txt`
   - Check port availability: `lsof -i :8001`

4. **SSL Certificate Expired**
   ```bash
   sudo certbot renew
   sudo systemctl reload nginx
   ```

### Debug Commands

```bash
# Check nginx configuration
sudo nginx -t

# Check SSL certificate
sudo certbot certificates

# Check service status
systemctl status aio-pod
systemctl status nginx

# Check logs
journalctl -u aio-pod -n 50
sudo tail -f /var/log/nginx/error.log

# Test endpoints
curl -v https://mcp.aio2030.fun/health
```

## Security Considerations

1. **Firewall**: UFW is configured to allow only necessary ports
2. **SSL**: TLS 1.2 and 1.3 are enforced
3. **Headers**: Security headers are added to prevent common attacks
4. **Rate Limiting**: API endpoints have rate limiting configured
5. **File Uploads**: Large file uploads are handled securely

## Backup and Recovery

### Backup Configuration
```bash
# Backup nginx config
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Backup SSL certificates
sudo cp -r /etc/letsencrypt /backup/letsencrypt
```

### Restore Configuration
```bash
# Restore nginx config
sudo cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl reload nginx

# Restore SSL certificates
sudo cp -r /backup/letsencrypt /etc/
```

## Maintenance

### Regular Tasks
1. **Certificate Renewal**: Automatic daily renewal is configured
2. **Log Rotation**: Nginx logs are automatically rotated
3. **Security Updates**: Keep nginx and certbot updated

### Monitoring
- Monitor certificate expiration: `sudo certbot certificates`
- Monitor nginx status: `systemctl status nginx`
- Monitor service logs: `journalctl -u aio-pod -f` 