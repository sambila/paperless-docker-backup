#!/bin/bash

# Smart Paperless-ngx Backup Script
# Freitag: Vollbackup | Samstag-Donnerstag: Inkrementelles Backup (letzte 4 Wochen)

set -e

# Konfiguration
CONTAINER_NAME="paperless-ngx"  # Anpassen an deinen Container-Namen
BASE_BACKUP_DIR="/backup/paperless"
LOG_FILE="$BASE_BACKUP_DIR/backup.log"
INCREMENTAL_DAYS=28  # 4 Wochen

# Datum und Wochentag ermitteln
CURRENT_DATE=$(date +%Y%m%d_%H%M%S)
CURRENT_WEEKDAY=$(date +%u)  # 1=Montag, 5=Freitag, 7=Sonntag
INCREMENTAL_DATE=$(date -d "$INCREMENTAL_DAYS days ago" +%Y-%m-%d)

# Backup-Typ bestimmen
if [ "$CURRENT_WEEKDAY" -eq 5 ]; then
    BACKUP_TYPE="FULL"
    BACKUP_DIR="$BASE_BACKUP_DIR/full_$CURRENT_DATE"
else
    BACKUP_TYPE="INCREMENTAL"
    BACKUP_DIR="$BASE_BACKUP_DIR/incremental_$CURRENT_DATE"
fi

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging Funktion
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [$BACKUP_TYPE]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] [$BACKUP_TYPE]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] [$BACKUP_TYPE]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO] [$BACKUP_TYPE]${NC} $1" | tee -a "$LOG_FILE"
}

# Backup Verzeichnis erstellen
mkdir -p "$BACKUP_DIR"
mkdir -p "$BASE_BACKUP_DIR"

# 1. Prüfen ob Container läuft
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    error "Container '$CONTAINER_NAME' läuft nicht!"
fi

log "Starte $BACKUP_TYPE Backup in: $BACKUP_DIR"

# Funktion für Vollbackup (Freitag)
full_backup() {
    log "Führe VOLLBACKUP durch..."
    
    # Komplette Datenbank
    log "Exportiere komplette Datenbank..."
    docker exec "$CONTAINER_NAME" python manage.py dumpdata \
        --natural-foreign --natural-primary \
        --exclude=contenttypes --exclude=auth.permission \
        --exclude=sessions.session --exclude=admin.logentry \
        > "$BACKUP_DIR/database_dump.json" || error "Datenbank Backup fehlgeschlagen"

    # Alle Dokumente exportieren
    log "Exportiere alle Originaldokumente..."
    docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/originals_full.tar.gz -C /usr/src/paperless/media documents/originals/" || warn "Originals Export fehlgeschlagen"
    docker cp "$CONTAINER_NAME:/tmp/originals_full.tar.gz" "$BACKUP_DIR/" || warn "Originals Copy fehlgeschlagen"

    log "Exportiere alle Archive..."
    docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/archive_full.tar.gz -C /usr/src/paperless/media documents/archive/" || warn "Archive Export fehlgeschlagen"
    docker cp "$CONTAINER_NAME:/tmp/archive_full.tar.gz" "$BACKUP_DIR/" || warn "Archive Copy fehlgeschlagen"

    log "Exportiere alle Thumbnails..."
    docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/thumbnails_full.tar.gz -C /usr/src/paperless/media documents/thumbnails/" || warn "Thumbnails Export fehlgeschlagen"
    docker cp "$CONTAINER_NAME:/tmp/thumbnails_full.tar.gz" "$BACKUP_DIR/" || warn "Thumbnails Copy fehlgeschlagen"

    # Komplettes Media Directory
    log "Exportiere komplettes Media Verzeichnis..."
    docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/media_full.tar.gz /usr/src/paperless/media/" || warn "Media Export fehlgeschlagen"
    docker cp "$CONTAINER_NAME:/tmp/media_full.tar.gz" "$BACKUP_DIR/" || warn "Media Copy fehlgeschlagen"

    # Separate JSON Exports
    export_entities_full
    
    # Cleanup
    docker exec "$CONTAINER_NAME" rm -f /tmp/*_full.tar.gz || true
}

# Funktion für inkrementelles Backup (Samstag-Donnerstag)
incremental_backup() {
    log "Führe INKREMENTELLES Backup durch (seit $INCREMENTAL_DATE)..."
    
    # Nur geänderte Dokumente seit X Tagen
    log "Suche Dokumente geändert seit $INCREMENTAL_DATE..."
    
    # Geänderte Dokumente aus Datenbank ermitteln
    docker exec "$CONTAINER_NAME" python manage.py shell << EOF > "$BACKUP_DIR/changed_documents.txt" || error "Geänderte Dokumente Query fehlgeschlagen"
from documents.models import Document
from django.utils import timezone
from datetime import datetime, timedelta
import os

cutoff_date = datetime.strptime('$INCREMENTAL_DATE', '%Y-%m-%d').replace(tzinfo=timezone.get_current_timezone())
changed_docs = Document.objects.filter(modified__gte=cutoff_date)

print(f"Gefundene geänderte Dokumente: {changed_docs.count()}")
for doc in changed_docs:
    if doc.original_file:
        print(f"ORIGINAL: {doc.original_file.name}")
    if doc.archive_file:
        print(f"ARCHIVE: {doc.archive_file.name}")
    if doc.thumbnail_file:
        print(f"THUMBNAIL: {doc.thumbnail_file.name}")
EOF

    # Nur geänderte Dokumente sichern
    if [ -s "$BACKUP_DIR/changed_documents.txt" ]; then
        log "Erstelle inkrementelles Archiv für geänderte Dokumente..."
        
        # Originals
        docker exec "$CONTAINER_NAME" sh -c "
            cd /usr/src/paperless/media
            find documents/originals -newer documents/originals -mtime -$INCREMENTAL_DAYS 2>/dev/null | tar -czf /tmp/originals_incremental.tar.gz -T - 2>/dev/null || echo 'Keine neuen Originals'
        " || warn "Incremental Originals fehlgeschlagen"
        
        # Archive
        docker exec "$CONTAINER_NAME" sh -c "
            cd /usr/src/paperless/media
            find documents/archive -mtime -$INCREMENTAL_DAYS 2>/dev/null | tar -czf /tmp/archive_incremental.tar.gz -T - 2>/dev/null || echo 'Keine neuen Archive'
        " || warn "Incremental Archive fehlgeschlagen"
        
        # Thumbnails
        docker exec "$CONTAINER_NAME" sh -c "
            cd /usr/src/paperless/media
            find documents/thumbnails -mtime -$INCREMENTAL_DAYS 2>/dev/null | tar -czf /tmp/thumbnails_incremental.tar.gz -T - 2>/dev/null || echo 'Keine neuen Thumbnails'
        " || warn "Incremental Thumbnails fehlgeschlagen"
        
        # Dateien kopieren (falls sie existieren)
        docker cp "$CONTAINER_NAME:/tmp/originals_incremental.tar.gz" "$BACKUP_DIR/" 2>/dev/null || warn "Keine incremental originals"
        docker cp "$CONTAINER_NAME:/tmp/archive_incremental.tar.gz" "$BACKUP_DIR/" 2>/dev/null || warn "Keine incremental archive"  
        docker cp "$CONTAINER_NAME:/tmp/thumbnails_incremental.tar.gz" "$BACKUP_DIR/" 2>/dev/null || warn "Keine incremental thumbnails"
    else
        info "Keine geänderten Dokumente gefunden"
    fi

    # Nur geänderte Metadaten seit X Tagen
    log "Exportiere geänderte Metadaten seit $INCREMENTAL_DATE..."
    export_entities_incremental
    
    # Cleanup
    docker exec "$CONTAINER_NAME" rm -f /tmp/*_incremental.tar.gz || true
}

# Vollständige Entity Exports
export_entities_full() {
    log "Exportiere alle Entitäten..."
    
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.tag --natural-foreign --natural-primary > "$BACKUP_DIR/tags.json" || warn "Tags Export fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.correspondent --natural-foreign --natural-primary > "$BACKUP_DIR/correspondents.json" || warn "Correspondents Export fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.documenttype --natural-foreign --natural-primary > "$BACKUP_DIR/document_types.json" || warn "Document Types Export fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.storagepath --natural-foreign --natural-primary > "$BACKUP_DIR/storage_paths.json" || warn "Storage Paths Export fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.document --natural-foreign --natural-primary > "$BACKUP_DIR/documents_metadata.json" || warn "Documents Metadata Export fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py dumpdata auth.user --natural-foreign --natural-primary > "$BACKUP_DIR/users.json" || warn "Users Export fehlgeschlagen"
}

# Inkrementelle Entity Exports
export_entities_incremental() {
    log "Exportiere nur geänderte Entitäten seit $INCREMENTAL_DATE..."
    
    # Nur geänderte Dokumente
    docker exec "$CONTAINER_NAME" python manage.py shell << EOF > "$BACKUP_DIR/incremental_documents.json" || warn "Incremental Documents Export fehlgeschlagen"
from documents.models import Document
from django.core import serializers
from django.utils import timezone
from datetime import datetime

cutoff_date = datetime.strptime('$INCREMENTAL_DATE', '%Y-%m-%d').replace(tzinfo=timezone.get_current_timezone())
changed_docs = Document.objects.filter(modified__gte=cutoff_date)

serialized = serializers.serialize('json', changed_docs, use_natural_foreign_keys=True, use_natural_primary_keys=True)
print(serialized)
EOF

    # Aktuelle Tags, Correspondents etc. (klein, daher immer komplett)
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.tag --natural-foreign --natural-primary > "$BACKUP_DIR/tags_current.json" || warn "Current Tags Export fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.correspondent --natural-foreign --natural-primary > "$BACKUP_DIR/correspondents_current.json" || warn "Current Correspondents Export fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.documenttype --natural-foreign --natural-primary > "$BACKUP_DIR/document_types_current.json" || warn "Current Document Types Export fehlgeschlagen"
}

# Backup-Informationen erstellen
create_backup_info() {
    cat > "$BACKUP_DIR/backup_info.txt" << EOF
Paperless-ngx Smart Backup
==========================
Backup-Typ: $BACKUP_TYPE
Datum: $(date)
Container: $CONTAINER_NAME
Backup Verzeichnis: $BACKUP_DIR

$(if [ "$BACKUP_TYPE" = "INCREMENTAL" ]; then
    echo "Inkrementell seit: $INCREMENTAL_DATE"
    echo "Tage: $INCREMENTAL_DAYS"
fi)

Paperless Version:
$(docker exec "$CONTAINER_NAME" python manage.py version 2>/dev/null || echo "Version nicht verfügbar")

Docker Image:
$(docker inspect "$CONTAINER_NAME" --format='{{.Config.Image}}')

Backup-Strategie:
- Freitag: Vollbackup (alle Daten)
- Samstag-Donnerstag: Inkrementell (nur Änderungen der letzten $INCREMENTAL_DAYS Tage)

Restore siehe: restore_instructions.txt
EOF

    # Restore-Anweisungen
    cat > "$BACKUP_DIR/restore_instructions.txt" << 'EOF'
Smart Backup Restore Anweisungen
================================

WICHTIG: Für komplettes Restore benötigst du:
1. Das neueste VOLLBACKUP (Freitag)
2. Alle INKREMENTELLEN Backups seit dem Vollbackup

RESTORE PROZESS:
===============

1. Container stoppen:
   docker-compose down

2. Volumes/Verzeichnisse leeren:
   docker volume rm paperless_media paperless_data

3. Container neu starten:
   docker-compose up -d && sleep 30

4. VOLLBACKUP wiederherstellen:
   cd /pfad/zum/vollbackup/
   docker cp database_dump.json CONTAINER:/tmp/
   docker exec CONTAINER python manage.py loaddata /tmp/database_dump.json
   
   docker cp originals_full.tar.gz CONTAINER:/tmp/
   docker cp archive_full.tar.gz CONTAINER:/tmp/
   docker cp thumbnails_full.tar.gz CONTAINER:/tmp/
   
   docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/originals_full.tar.gz"
   docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/archive_full.tar.gz"
   docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/thumbnails_full.tar.gz"

5. INKREMENTELLE Backups anwenden (chronologisch):
   for incremental_backup in incremental_*/; do
     cd "$incremental_backup"
     
     # Falls vorhanden: Dokument-Updates
     if [ -f incremental_documents.json ]; then
       docker cp incremental_documents.json CONTAINER:/tmp/
       docker exec CONTAINER python manage.py loaddata /tmp/incremental_documents.json
     fi
     
     # Falls vorhanden: Neue Dateien
     [ -f originals_incremental.tar.gz ] && docker cp originals_incremental.tar.gz CONTAINER:/tmp/ && docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/originals_incremental.tar.gz"
     [ -f archive_incremental.tar.gz ] && docker cp archive_incremental.tar.gz CONTAINER:/tmp/ && docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/archive_incremental.tar.gz"
     [ -f thumbnails_incremental.tar.gz ] && docker cp thumbnails_incremental.tar.gz CONTAINER:/tmp/ && docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/thumbnails_incremental.tar.gz"
     
     cd ..
   done

6. Permissions korrigieren:
   docker exec CONTAINER chown -R paperless:paperless /usr/src/paperless/media

7. Search Index neu aufbauen:
   docker exec CONTAINER python manage.py document_index reindex

8. Container neustarten:
   docker-compose restart

AUTOMATISIERTES RESTORE SCRIPT:
==============================
Ein separates restore_smart_backup.sh Script wird empfohlen!
EOF
}

# Hauptlogik
if [ "$BACKUP_TYPE" = "FULL" ]; then
    full_backup
else
    incremental_backup
fi

# Backup-Informationen erstellen
create_backup_info

# Backup-Größe berechnen
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "Backup abgeschlossen!"
log "Backup-Typ: $BACKUP_TYPE"
log "Backup-Größe: $BACKUP_SIZE"
log "Backup-Verzeichnis: $BACKUP_DIR"

# Alte Backups aufräumen (optional)
log "Räume alte Backups auf..."

# Behalte nur letzte 4 Vollbackups
find "$BASE_BACKUP_DIR" -name "full_*" -type d -mtime +28 -exec rm -rf {} \; 2>/dev/null || true

# Behalte inkrementelle Backups nur 5 Wochen
find "$BASE_BACKUP_DIR" -name "incremental_*" -type d -mtime +35 -exec rm -rf {} \; 2>/dev/null || true

log "Smart Backup Script beendet!"
echo ""
info "Nächster Backup-Typ: $(if [ "$CURRENT_WEEKDAY" -eq 5 ]; then echo "INCREMENTAL (Samstag-Donnerstag)"; else echo "FULL (Freitag)"; fi)"