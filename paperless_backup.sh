#!/bin/bash

# Paperless-ngx Backup Script
# Exportiert alle Dokumente, Metadaten und Konfigurationen

set -e

# Konfiguration
CONTAINER_NAME="paperless-ngx"  # Anpassen an deinen Container-Namen
BACKUP_DIR="/backup/paperless/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$BACKUP_DIR/backup.log"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging Funktion
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Backup Verzeichnis erstellen
mkdir -p "$BACKUP_DIR"
log "Backup gestartet in: $BACKUP_DIR"

# 1. Prüfen ob Container läuft
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    error "Container '$CONTAINER_NAME' läuft nicht!"
fi

# 2. Datenbank Backup (SQLite oder PostgreSQL)
log "Erstelle Datenbank Backup..."
docker exec "$CONTAINER_NAME" python manage.py dumpdata \
    --natural-foreign --natural-primary \
    --exclude=contenttypes --exclude=auth.permission \
    --exclude=sessions.session --exclude=admin.logentry \
    > "$BACKUP_DIR/database_dump.json" || error "Datenbank Backup fehlgeschlagen"

# 3. Dokumente exportieren (Originale + OCR)
log "Exportiere Originaldokumente..."
docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/originals.tar.gz -C /usr/src/paperless/media documents/originals/" || warn "Originals Export fehlgeschlagen"
docker cp "$CONTAINER_NAME:/tmp/originals.tar.gz" "$BACKUP_DIR/" || warn "Originals Copy fehlgeschlagen"

log "Exportiere Archive (OCR Dokumente)..."
docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/archive.tar.gz -C /usr/src/paperless/media documents/archive/" || warn "Archive Export fehlgeschlagen"
docker cp "$CONTAINER_NAME:/tmp/archive.tar.gz" "$BACKUP_DIR/" || warn "Archive Copy fehlgeschlagen"

# 4. Thumbnails exportieren
log "Exportiere Thumbnails..."
docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/thumbnails.tar.gz -C /usr/src/paperless/media documents/thumbnails/" || warn "Thumbnails Export fehlgeschlagen"
docker cp "$CONTAINER_NAME:/tmp/thumbnails.tar.gz" "$BACKUP_DIR/" || warn "Thumbnails Copy fehlgeschlagen"

# 5. Konfigurationsdateien
log "Exportiere Konfiguration..."
# Media Verzeichnis komplett
docker exec "$CONTAINER_NAME" sh -c "tar -czf /tmp/media.tar.gz /usr/src/paperless/media/" || warn "Media Export fehlgeschlagen"
docker cp "$CONTAINER_NAME:/tmp/media.tar.gz" "$BACKUP_DIR/" || warn "Media Copy fehlgeschlagen"

# 6. Separate Exports für wichtige Entities
log "Exportiere spezifische Datenmodelle..."

# Tags
docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.tag \
    --natural-foreign --natural-primary \
    > "$BACKUP_DIR/tags.json" || warn "Tags Export fehlgeschlagen"

# Correspondents (Korrespondenten)
docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.correspondent \
    --natural-foreign --natural-primary \
    > "$BACKUP_DIR/correspondents.json" || warn "Correspondents Export fehlgeschlagen"

# Document Types
docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.documenttype \
    --natural-foreign --natural-primary \
    > "$BACKUP_DIR/document_types.json" || warn "Document Types Export fehlgeschlagen"

# Storage Paths
docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.storagepath \
    --natural-foreign --natural-primary \
    > "$BACKUP_DIR/storage_paths.json" || warn "Storage Paths Export fehlgeschlagen"

# Dokumente Metadaten
docker exec "$CONTAINER_NAME" python manage.py dumpdata documents.document \
    --natural-foreign --natural-primary \
    > "$BACKUP_DIR/documents_metadata.json" || warn "Documents Metadata Export fehlgeschlagen"

# Users
docker exec "$CONTAINER_NAME" python manage.py dumpdata auth.user \
    --natural-foreign --natural-primary \
    > "$BACKUP_DIR/users.json" || warn "Users Export fehlgeschlagen"

# 7. Cleanup temporärer Dateien im Container
log "Cleanup temporärer Dateien..."
docker exec "$CONTAINER_NAME" rm -f /tmp/*.tar.gz || true

# 8. Backup Informationen
log "Erstelle Backup Informationen..."
cat > "$BACKUP_DIR/backup_info.txt" << EOF
Paperless-ngx Backup
====================
Datum: $(date)
Container: $CONTAINER_NAME
Backup Verzeichnis: $BACKUP_DIR

Paperless Version:
$(docker exec "$CONTAINER_NAME" python manage.py version 2>/dev/null || echo "Version nicht verfügbar")

Docker Image:
$(docker inspect "$CONTAINER_NAME" --format='{{.Config.Image}}')

Enthaltene Dateien:
- database_dump.json (Komplette Datenbank)
- originals.tar.gz (Original Dokumente)
- archive.tar.gz (OCR/Archiv Dokumente)
- thumbnails.tar.gz (Vorschaubilder)
- media.tar.gz (Komplettes Media Verzeichnis)
- tags.json (Tags)
- correspondents.json (Korrespondenten)
- document_types.json (Dokumenttypen)
- storage_paths.json (Speicherpfade)
- documents_metadata.json (Dokument Metadaten)
- users.json (Benutzer)

Restore Befehle siehe restore_instructions.txt
EOF

# 9. Restore Anweisungen
cat > "$BACKUP_DIR/restore_instructions.txt" << 'EOF'
Paperless-ngx Restore Anweisungen
=================================

1. Container stoppen:
   docker-compose down

2. Volumes/Verzeichnisse leeren:
   docker volume rm paperless_media paperless_data
   # oder bei bind mounts die Verzeichnisse leeren

3. Container neu starten:
   docker-compose up -d

4. Warten bis Container bereit ist, dann Datenbank restore:
   docker cp database_dump.json CONTAINER:/tmp/
   docker exec CONTAINER python manage.py loaddata /tmp/database_dump.json

5. Dokumente restore:
   docker cp originals.tar.gz CONTAINER:/tmp/
   docker cp archive.tar.gz CONTAINER:/tmp/
   docker cp thumbnails.tar.gz CONTAINER:/tmp/
   
   docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/originals.tar.gz"
   docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/archive.tar.gz"
   docker exec CONTAINER sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/thumbnails.tar.gz"

6. Permissions korrigieren:
   docker exec CONTAINER chown -R paperless:paperless /usr/src/paperless/media

7. Search Index neu aufbauen:
   docker exec CONTAINER python manage.py document_index reindex

8. Container neustarten:
   docker-compose restart
EOF

# 10. Backup Größe berechnen
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "Backup abgeschlossen!"
log "Backup Größe: $BACKUP_SIZE"
log "Backup Verzeichnis: $BACKUP_DIR"

# 11. Optional: Backup komprimieren
read -p "Backup als tar.gz komprimieren? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Komprimiere Backup..."
    tar -czf "${BACKUP_DIR}.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
    log "Komprimiertes Backup: ${BACKUP_DIR}.tar.gz"
    
    read -p "Original Backup Verzeichnis löschen? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$BACKUP_DIR"
        log "Original Backup Verzeichnis gelöscht"
    fi
fi

log "Backup Script beendet!"