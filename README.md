# Paperless-ngx Docker Backup Scripts

🗂️ **Complete backup solution for Paperless-ngx Docker containers**

Professional backup system with smart full/incremental strategy for optimal storage efficiency and reliable restores.

## 🎯 Smart Backup Strategy

### 📅 Automated Schedule
- **Friday**: Full backup (all data)
- **Saturday-Thursday**: Incremental backup (changes from last 4 weeks)

### ✅ Benefits
- **Space efficient**: Incremental backups save 80-90% storage
- **Fast daily backups**: Only changed data is backed up
- **Safe restores**: Never breaks - combines full + incremental perfectly
- **Automatic cleanup**: Old backups are automatically removed

## 📋 What gets backed up

- **Complete Database** - All metadata, tags, correspondents, document types, etc.
- **Original Documents** - Files as uploaded
- **Archive Documents** - OCR-processed versions
- **Thumbnails** - Preview images
- **Configuration** - All settings and customizations
- **Individual JSON exports** for granular restore options

## 🚀 Quick Start

### 1. Download Scripts
```bash
# Smart backup (recommended)
wget https://raw.githubusercontent.com/sambila/paperless-docker-backup/main/paperless_smart_backup.sh
chmod +x paperless_smart_backup.sh

# Smart restore
wget https://raw.githubusercontent.com/sambila/paperless-docker-backup/main/paperless_smart_restore.sh
chmod +x paperless_smart_restore.sh

# Simple backup (full backup every time)
wget https://raw.githubusercontent.com/sambila/paperless-docker-backup/main/paperless_backup.sh
chmod +x paperless_backup.sh
```

### 2. Configure Container Name
Edit the scripts and change `CONTAINER_NAME`:
```bash
CONTAINER_NAME="your-paperless-container-name"
```

### 3. Setup Automated Backups
Add to crontab for daily automatic backups:
```bash
# Smart backup daily at 2 AM
0 2 * * * /path/to/paperless_smart_backup.sh

# Or simple full backup weekly
0 2 * * 0 /path/to/paperless_backup.sh
```

## 📦 Available Scripts

### 🧠 Smart Backup (`paperless_smart_backup.sh`)
**Recommended for production use**

- **Friday**: Complete full backup
- **Saturday-Thursday**: Incremental changes only
- **Automatic cleanup**: Keeps 4 weeks of backups
- **Space efficient**: 80-90% storage savings

```bash
./paperless_smart_backup.sh
```

### 🔄 Smart Restore (`paperless_smart_restore.sh`)
**Automated restore with intelligence**

```bash
# Restore to latest backup
./paperless_smart_restore.sh latest

# Restore to specific date
./paperless_smart_restore.sh 2025-08-15
```

Features:
- **Automatic detection**: Finds correct full + incremental backups
- **Safe restore**: Backs up current state before restore
- **Health check**: Verifies restore completeness
- **Step-by-step**: Clear progress indication

### 🔧 Simple Backup (`paperless_backup.sh`)
**Full backup every time**

- Creates complete backup each run
- Larger storage requirements
- Good for testing or infrequent backups

```bash
./paperless_backup.sh
```

## ⚙️ Configuration

### Container Name
Update in all scripts:
```bash
CONTAINER_NAME="paperless-ngx"  # Change this
```

### Backup Directory
Default: `/backup/paperless/`. Change if needed:
```bash
BASE_BACKUP_DIR="/your/backup/path"
```

### Incremental Period
Smart backup default: 28 days (4 weeks). Adjust if needed:
```bash
INCREMENTAL_DAYS=28  # Days to include in incremental
```

## 📁 Backup Structure

### Smart Backup Structure
```
/backup/paperless/
├── full_20250819_020000/          # Friday full backup
│   ├── database_dump.json
│   ├── originals_full.tar.gz
│   ├── archive_full.tar.gz
│   ├── thumbnails_full.tar.gz
│   ├── tags.json
│   └── ...
├── incremental_20250820_020000/   # Saturday incremental
│   ├── incremental_documents.json
│   ├── originals_incremental.tar.gz
│   ├── tags_current.json
│   └── ...
├── incremental_20250821_020000/   # Sunday incremental
└── ...
```

### Simple Backup Structure
```
backup_YYYYMMDD_HHMMSS/
├── backup.log
├── backup_info.txt
├── restore_instructions.txt
├── database_dump.json
├── originals.tar.gz
├── archive.tar.gz
├── thumbnails.tar.gz
├── tags.json
├── correspondents.json
└── ...
```

## 🔄 Restore Examples

### Smart Restore Usage
```bash
# Restore latest backup automatically
./paperless_smart_restore.sh latest

# Restore to specific date (finds best backup combination)
./paperless_smart_restore.sh 2025-08-15

# What it does automatically:
# 1. Finds newest full backup before date
# 2. Finds all incremental backups since full backup
# 3. Applies them in correct order
# 4. Runs health check
```

### Manual Restore Process
For understanding or troubleshooting:

1. **Stop container**
2. **Apply full backup** (database + all files)
3. **Apply incremental backups** in chronological order
4. **Fix permissions** and rebuild search index
5. **Restart container**

## 🔧 Compatibility

- **Paperless-ngx** (all versions)
- **Docker** and **Docker Compose**
- **Linux/Unix** systems
- **SQLite** and **PostgreSQL** backends

## 📝 Usage Examples

### Docker Compose
If using docker-compose, you might need to adjust commands:
```bash
# In scripts, change:
# docker exec container-name
# to:
# docker-compose exec paperless
```

### Custom Backup Location
```bash
# For NAS or network storage
BASE_BACKUP_DIR="/mnt/nas/paperless-backups"
```

### Testing Backups
```bash
# Test restore to verify backup integrity
./paperless_smart_restore.sh latest

# Run health check after restore
# (included in restore script)
```

## ⚠️ Important Notes

### Smart Backup
- **Requires consistent schedule**: Friday full backups are essential
- **4-week window**: Incremental backups include changes from last 28 days
- **Storage calculation**: Full backup size + ~20% for incrementals

### General
- **Container must be running** during backup
- **Sufficient disk space** required
- **Test restore process** in development first
- **Monitor backup logs** for any issues

## 🤝 Contributing

Contributions welcome! Areas for improvement:
- Better error handling
- Support for more backup destinations
- GUI interface
- Backup verification tools

## 📄 License

MIT License - free to use and modify.

## 🆘 Support

If you encounter issues:

1. **Check container name** is correct in scripts
2. **Ensure container is running**
3. **Verify disk space** is sufficient
4. **Check backup logs** for error details
5. **Test with simple backup** first if smart backup fails

### Common Issues
- **Permission errors**: Run scripts as user with Docker access
- **Large backups**: Consider network storage for backup destination
- **Failed incrementals**: Check if Friday full backup exists
- **Restore failures**: Verify all required backup files are present

---

**Made for the Paperless-ngx community** 📄✨

Choose your backup strategy:
- **🧠 Smart Backup**: Production use, space efficient
- **🔧 Simple Backup**: Testing, one-time backups