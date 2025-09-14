# Paperless-NGX Backup and Restore

## Overview

Paperless data is stored in ZFS datasets on SSD-backed rpool for performance and snapshotting:
- `/var/lib/paperless` → `rpool/nixos/var/lib/paperless/app`  
- `/var/lib/containers/storage/volumes/paperless-ai-data/_data` → `rpool/nixos/var/lib/paperless/ai`

Both datasets are replicated to tank pool using sanoid/syncoid for local backup.

## Backup Components

### 1. Database (PostgreSQL)
```bash
# Manual backup from odroid
ssh flakm@odroid "sudo -u postgres pg_dump paperless" > paperless_backup.sql

# Restore to Docker container
docker compose exec -T db psql -U paperless -d paperless < paperless_backup.sql

# Note: PostgreSQL data on odroid is stored in /var/lib/postgresql/14, not in the ZFS dataset
# The rpool/nixos/var/lib/postgres dataset appears to be unused
```

### 2. Media Files and Documents
```bash
# ZFS snapshots (automated via sanoid)
zfs snapshot rpool/nixos/var/lib/paperless/app@backup-$(date +%Y%m%d-%H%M%S)
zfs snapshot rpool/nixos/var/lib/paperless/ai@backup-$(date +%Y%m%d-%H%M%S)

# Manual file backup
tar -czf paperless-media-$(date +%Y%m%d).tar.gz /var/lib/paperless/media
tar -czf paperless-data-$(date +%Y%m%d).tar.gz /var/lib/paperless/data
```

### 3. Paperless-AI Data
```bash
# Container volume backup
tar -czf paperless-ai-$(date +%Y%m%d).tar.gz /var/lib/containers/storage/volumes/paperless-ai-data/_data
```

## Simplified Restore Using ZFS Snapshots

### 1. Restore from odroid to amd-pc

```bash
# On amd-pc, create restore datasets
sudo zfs create -p rpool/restore/paperless/app
sudo zfs create -p rpool/restore/paperless/ai  
sudo zfs create -p rpool/restore/postgres

# Find and restore latest snapshots (replace SNAPSHOT_NAME with actual latest snapshot)
# List available snapshots:
ssh flakm@odroid "zfs list -t snapshot | grep -E 'rpool/nixos/var/lib/(paperless|postgres)@.*hourly' | tail -3"

# Pull specific snapshots directly from odroid (example with latest hourly snapshot)
ssh flakm@odroid "sudo zfs send rpool/nixos/var/lib/paperless/app@autosnap_2025-09-14_19:00:26_hourly" | sudo zfs receive -F rpool/restore/paperless/app

ssh flakm@odroid "sudo zfs send rpool/nixos/var/lib/paperless/ai@autosnap_2025-09-14_19:00:26_hourly" | sudo zfs receive -F rpool/restore/paperless/ai

# PostgreSQL data is now stored in dedicated ZFS dataset for snapshot restore
ssh flakm@odroid "sudo zfs send rpool/nixos/var/lib/postgresql@autosnap_2025-09-14_19:00:26_hourly" | sudo zfs receive -F rpool/restore/postgresql

# Set mountpoints for Docker access
sudo zfs set mountpoint=/tmp/restore/paperless rpool/restore/paperless/app
sudo zfs set mountpoint=/tmp/restore/paperless-ai rpool/restore/paperless/ai
sudo zfs set mountpoint=/tmp/restore/postgresql rpool/restore/postgresql

# Verify data is accessible
ls -la /tmp/restore/paperless/
ls -la /tmp/restore/paperless-ai/
sudo ls -la /tmp/restore/postgresql/
```

### 2. Run with Docker Using ZFS Data

```bash
# Fix potential Docker network issues
docker network create --driver bridge --subnet=172.20.0.0/16 paperless-net

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
networks:
  default:
    external: true
    name: paperless-net

services:
  paperless-ngx:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    restart: unless-stopped
    depends_on:
      - db
      - redis
    ports:
      - "127.0.0.1:8080:8000"
    volumes:
      - /tmp/restore/paperless/media:/usr/src/paperless/media
      - /tmp/restore/paperless/data:/usr/src/paperless/data
      - /tmp/restore/paperless/consume:/usr/src/paperless/consume
    environment:
      PAPERLESS_REDIS: redis://redis:6379
      PAPERLESS_DBHOST: db
      PAPERLESS_DBUSER: paperless
      PAPERLESS_DBPASS: paperless
      PAPERLESS_DBNAME: paperless
      PAPERLESS_SECRET_KEY: change-me-for-production
      PAPERLESS_URL: http://localhost:8080
      PAPERLESS_TIME_ZONE: Europe/Warsaw
      PAPERLESS_OCR_LANGUAGE: eng

  db:
    image: postgres:14
    restart: unless-stopped
    volumes:
      - /tmp/restore/postgresql/14:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: paperless
      POSTGRES_USER: paperless
      POSTGRES_PASSWORD: paperless
      POSTGRES_HOST_AUTH_METHOD: trust

  redis:
    image: redis:7
    restart: unless-stopped

  paperless-ai:
    image: clusterzx/paperless-ai:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:3011:3000"
    volumes:
      - /tmp/restore/paperless-ai:/app/data
    environment:
      PAPERLESS_AI_PORT: "3000"

volumes:
  paperless-db-data:
EOF

# Fix PostgreSQL configuration (NixOS symlink issues)
sudo rm /tmp/restore/postgresql/14/postgresql.conf
docker run --rm postgres:14 cat /usr/share/postgresql/postgresql.conf.sample | sudo tee /tmp/restore/postgresql/14/postgresql.conf > /dev/null

# Fix PostgreSQL authentication for Docker containers
sudo sh -c 'echo "host    all             all             172.20.0.0/16           trust" >> /tmp/restore/postgresql/14/pg_hba.conf'

# Set correct ownership for PostgreSQL
sudo chown -R 999:999 /tmp/restore/postgresql/14

# Start services with restored data
docker compose up -d

# Check status
docker compose ps

# View logs if needed
docker compose logs paperless-ngx --tail 20

# Verify database restore worked
docker compose exec db psql -U paperless -d paperless -c "SELECT COUNT(*) FROM documents_document;"
docker compose exec db psql -U paperless -d paperless -c "SELECT title FROM documents_document LIMIT 3;"
```

### 3. Access Restored Instance

- **Paperless-NGX**: http://localhost:8080
- **Paperless-AI**: http://localhost:3011

### 4. Troubleshooting Docker Deployment

**Common Issues:**

1. **Network conflicts**: If you get "all predefined address pools have been fully subnetted"
   ```bash
   docker network create --driver bridge --subnet=172.20.0.0/16 paperless-net
   ```

2. **OCR language errors**: If Polish language is not available, use English only:
   ```yaml
   PAPERLESS_OCR_LANGUAGE: eng
   ```

3. **Permission issues**: Media files might need permission adjustments:
   ```bash
   sudo chmod -R 755 /tmp/restore/paperless/media
   ```

4. **Database issues**: Start with fresh database if corrupted:
   ```bash
   docker volume rm paperless-db-data
   ```

5. **Server 500 errors with ZFS-restored database**: PostgreSQL authentication needs Docker network access:
   ```bash
   sudo sh -c 'echo "host    all             all             172.20.0.0/16           trust" >> /tmp/restore/postgresql/14/pg_hba.conf'
   docker compose restart db paperless-ngx
   ```

**Testing:**
```bash
# Check service health
curl -s -o /dev/null -w '%{http_code}' http://localhost:8080  # Should return 302
curl -s -o /dev/null -w '%{http_code}' http://localhost:3011  # Should return 302

# Check if media files are accessible
find /tmp/restore/paperless/media -type f | wc -l
```

## ZFS Dataset Management

### Current Setup
```bash
# Check dataset status
zfs list | grep paperless
zfs get compression,used,available rpool/nixos/var/lib/paperless/app
zfs get compression,used,available rpool/nixos/var/lib/paperless/ai

# Manual snapshots
zfs snapshot rpool/nixos/var/lib/paperless/app@manual-$(date +%Y%m%d-%H%M%S)
zfs snapshot rpool/nixos/var/lib/paperless/ai@manual-$(date +%Y%m%d-%H%M%S)

# List snapshots
zfs list -t snapshot | grep paperless
```

### Replication Status
```bash
# Check sanoid/syncoid status
systemctl status sanoid.timer
systemctl status syncoid@rpool/nixos/var/lib/paperless/app
systemctl status syncoid@rpool/nixos/var/lib/paperless/ai

# Manual replication to tank
syncoid rpool/nixos/var/lib/paperless/app tank/backups/odroid/paperless/app
syncoid rpool/nixos/var/lib/paperless/ai tank/backups/odroid/paperless/ai
```

## Recovery Procedures

### From ZFS Snapshots
```bash
# List available snapshots
zfs list -t snapshot | grep paperless

# Rollback to snapshot (destructive)
systemctl stop paperless-scheduler paperless-consumer paperless-web
systemctl stop podman-paperless-ai
zfs rollback rpool/nixos/var/lib/paperless/app@snapshot-name
zfs rollback rpool/nixos/var/lib/paperless/ai@snapshot-name
systemctl start paperless-scheduler paperless-consumer paperless-web
systemctl start podman-paperless-ai
```

### From Tank Pool Backup
```bash
# Restore from tank pool
systemctl stop paperless-scheduler paperless-consumer paperless-web
systemctl stop podman-paperless-ai
syncoid tank/backups/odroid/paperless/app rpool/nixos/var/lib/paperless/app
syncoid tank/backups/odroid/paperless/ai rpool/nixos/var/lib/paperless/ai
systemctl start paperless-scheduler paperless-consumer paperless-web
systemctl start podman-paperless-ai
```

## Automation

Backups are automated via:
- **Sanoid**: Creates automatic ZFS snapshots
- **Syncoid**: Replicates snapshots to tank pool
- **PostgreSQL**: Included in system-wide database backup strategy

Configuration managed through NixOS modules in `/hosts/odroid/paperless.nix`.



I think the instruction for restore could be simplified a bit.
Use zfs receive from snapshots from amd-pc to restore both databases and media files.
Use the dockerfile to run using data from zfs datasets though - that seems like a good idea.

