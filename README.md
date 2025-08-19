# Paperless-ngx Docker Backup Script

🗂️ **Complete backup solution for Paperless-ngx Docker containers**

This script creates comprehensive backups of your Paperless-ngx installation, including all documents, metadata, configurations, and database content.

## 📋 What gets backed up

- **Complete Database** - All metadata, tags, correspondents, document types, etc.
- **Original Documents** - Files as uploaded
- **Archive Documents** - OCR-processed versions
- **Thumbnails** - Preview images
- **Configuration** - All settings and customizations
- **Individual JSON exports** for:
  - Tags
  - Correspondents
  - Document Types
  - Storage Paths
  - Document Metadata
  - Users

## 🚀 Quick Start

1. **Download the script:**
   ```bash
   wget https://raw.githubusercontent.com/sambila/paperless-docker-backup/main/paperless_backup.sh
   chmod +x paperless_backup.sh
   ```

2. **Configure container name:**
   Edit the script and change `CONTAINER_NAME` to match your Paperless container:
   ```bash
   CONTAINER_NAME="your-paperless-container-name"
   ```

3. **Run the backup:**
   ```bash
   ./paperless_backup.sh
   ```

## ⚙️ Configuration

### Container Name
Update the container name in the script:
```bash
CONTAINER_NAME="paperless-ngx"  # Change this to your container name
```

### Backup Directory
By default, backups are stored in `/backup/paperless/YYYYMMDD_HHMMSS`. Change this if needed:
```bash
BACKUP_DIR="/your/backup/path/$(date +%Y%m%d_%H%M%S)"
```

## 📁 Backup Structure

After running, your backup will contain:
```
backup_YYYYMMDD_HHMMSS/
├── backup.log                 # Backup process log
├── backup_info.txt           # Backup metadata and info
├── restore_instructions.txt  # Step-by-step restore guide
├── database_dump.json        # Complete database export
├── originals.tar.gz         # Original uploaded documents
├── archive.tar.gz           # OCR-processed documents
├── thumbnails.tar.gz        # Preview thumbnails
├── media.tar.gz             # Complete media directory
├── tags.json                # Tags export
├── correspondents.json      # Correspondents export
├── document_types.json      # Document types export
├── storage_paths.json       # Storage paths export
├── documents_metadata.json  # Document metadata
└── users.json              # Users export
```

## 🔄 Restore Process

Detailed restore instructions are automatically created in `restore_instructions.txt` with each backup.

**Quick restore overview:**
1. Stop Paperless container
2. Clear existing data volumes
3. Start container
4. Restore database: `docker exec CONTAINER python manage.py loaddata /tmp/database_dump.json`
5. Extract document archives
6. Fix permissions
7. Rebuild search index
8. Restart container

## 🔧 Compatibility

- **Paperless-ngx** (all versions)
- **Docker** and **Docker Compose**
- **Linux/Unix** systems
- Works with both **SQLite** and **PostgreSQL** backends

## 📝 Usage Examples

### Docker Compose
If using docker-compose, you might need to adjust commands:
```bash
# Instead of: docker exec paperless-ngx
# Use: docker-compose exec paperless
```

### Automated Backups
Add to crontab for automated backups:
```bash
# Daily backup at 2 AM
0 2 * * * /path/to/paperless_backup.sh
```

### Custom Backup Location
```bash
# Edit script to change backup directory
BACKUP_DIR="/mnt/nas/paperless-backups/$(date +%Y%m%d_%H%M%S)"
```

## ⚠️ Important Notes

- **Container must be running** during backup
- **Sufficient disk space** required (backup can be large)
- **Test restore process** in development environment first
- **Backup compression** option available (reduces size significantly)

## 🤝 Contributing

Contributions welcome! Please feel free to submit issues, feature requests, or pull requests.

## 📄 License

MIT License - feel free to use and modify as needed.

## 🆘 Support

If you encounter issues:
1. Check that your container name is correct
2. Ensure container is running
3. Verify sufficient disk space
4. Check container logs for Paperless-specific errors

---

**Made for the Paperless-ngx community** 📄✨