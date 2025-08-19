#!/bin/bash

# Smart Paperless-ngx Restore Script
# Stellt Vollbackup + alle inkrementellen Backups automatisch wieder her

set -e

# Konfiguration
CONTAINER_NAME="paperless-ngx"  # Anpassen an deinen Container-Namen
BACKUP_BASE_DIR="/backup/paperless"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [RESTORE]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR] [RESTORE]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] [RESTORE]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO] [RESTORE]${NC} $1"
}

# Hilfsfunktion: Benutzer-Bestätigung
confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Parameter prüfen
if [ $# -eq 0 ]; then
    echo "Smart Paperless-ngx Restore Script"
    echo "=================================="
    echo ""
    echo "Verwendung:"
    echo "  $0 [RESTORE_DATUM]"
    echo ""
    echo "Beispiele:"
    echo "  $0 2025-08-15    # Restore bis zu diesem Datum"
    echo "  $0 latest        # Restore mit neuestem verfügbaren Backup"
    echo ""
    echo "Das Script sucht automatisch:"
    echo "  1. Das neueste Vollbackup vor/am angegebenen Datum"
    echo "  2. Alle inkrementellen Backups seit dem Vollbackup"
    echo ""
    exit 1
fi

RESTORE_DATE="$1"

# Neuestes Backup suchen wenn "latest" angegeben
if [ "$RESTORE_DATE" = "latest" ]; then
    RESTORE_DATE=$(date +%Y-%m-%d)
    info "Verwende aktuelles Datum für Restore: $RESTORE_DATE"
fi

# Datum validieren
if ! date -d "$RESTORE_DATE" >/dev/null 2>&1; then
    error "Ungültiges Datum: $RESTORE_DATE (Format: YYYY-MM-DD)"
fi

log "Starte Smart Restore für Datum: $RESTORE_DATE"

# Backup-Verzeichnisse finden
log "Suche verfügbare Backups..."

# Neuestes Vollbackup vor dem Restore-Datum finden
FULL_BACKUP=$(find "$BACKUP_BASE_DIR" -name "full_*" -type d | while read dir; do
    backup_date=$(basename "$dir" | sed 's/full_\([0-9]\{8\}\)_.*/\1/')
    formatted_date=$(echo "$backup_date" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')
    
    if [[ "$formatted_date" <= "$RESTORE_DATE" ]]; then
        echo "$formatted_date $dir"
    fi
done | sort -r | head -n1 | cut -d' ' -f2)

if [ -z "$FULL_BACKUP" ]; then
    error "Kein Vollbackup vor/am $RESTORE_DATE gefunden!"
fi

FULL_BACKUP_DATE=$(basename "$FULL_BACKUP" | sed 's/full_\([0-9]\{8\}\)_.*/\1-\2-\3/' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')
log "Gefundenes Vollbackup: $FULL_BACKUP (Datum: $FULL_BACKUP_DATE)"

# Inkrementelle Backups seit Vollbackup finden
log "Suche inkrementelle Backups seit $FULL_BACKUP_DATE..."

INCREMENTAL_BACKUPS=$(find "$BACKUP_BASE_DIR" -name "incremental_*" -type d | while read dir; do
    backup_date=$(basename "$dir" | sed 's/incremental_\([0-9]\{8\}\)_.*/\1/')
    formatted_date=$(echo "$backup_date" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')
    
    if [[ "$formatted_date" > "$FULL_BACKUP_DATE" && "$formatted_date" <= "$RESTORE_DATE" ]]; then
        echo "$formatted_date $dir"
    fi
done | sort)

INCREMENTAL_COUNT=$(echo "$INCREMENTAL_BACKUPS" | grep -c . || echo "0")
info "Gefundene inkrementelle Backups: $INCREMENTAL_COUNT"

if [ "$INCREMENTAL_COUNT" -gt 0 ]; then
    echo "$INCREMENTAL_BACKUPS" | while read line; do
        info "  - $(echo "$line" | cut -d' ' -f2) ($(echo "$line" | cut -d' ' -f1))"
    done
fi

echo ""
log "RESTORE PLAN:"
log "============="
log "1. Vollbackup: $FULL_BACKUP"
if [ "$INCREMENTAL_COUNT" -gt 0 ]; then
    log "2. Inkrementelle Backups: $INCREMENTAL_COUNT Stück"
else
    log "2. Inkrementelle Backups: Keine"
fi
echo ""

# Bestätigung
if ! confirm "⚠️  ACHTUNG: Alle aktuellen Paperless-Daten werden überschrieben! Fortfahren?"; then
    error "Restore abgebrochen"
fi

# Container-Status prüfen
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    warn "Container '$CONTAINER_NAME' läuft nicht. Starte Container..."
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose up -d
    else
        docker start "$CONTAINER_NAME" || error "Container konnte nicht gestartet werden"
    fi
    sleep 30
fi

# Volumes backup (optional)
if confirm "Aktuellen Zustand vor Restore sichern?"; then
    BACKUP_CURRENT_DIR="/backup/paperless/pre_restore_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_CURRENT_DIR"
    log "Sichere aktuellen Zustand nach: $BACKUP_CURRENT_DIR"
    
    docker exec "$CONTAINER_NAME" python manage.py dumpdata \
        --natural-foreign --natural-primary \
        --exclude=contenttypes --exclude=auth.permission \
        --exclude=sessions.session --exclude=admin.logentry \
        > "$BACKUP_CURRENT_DIR/current_database.json" || warn "Current backup fehlgeschlagen"
fi

# 1. Vollbackup wiederherstellen
log "Schritt 1: Vollbackup wiederherstellen..."
cd "$FULL_BACKUP"

# Datenbank
if [ -f "database_dump.json" ]; then
    log "Stelle Datenbank wieder her..."
    docker cp database_dump.json "$CONTAINER_NAME:/tmp/"
    docker exec "$CONTAINER_NAME" python manage.py flush --no-input || warn "DB flush fehlgeschlagen"
    docker exec "$CONTAINER_NAME" python manage.py loaddata /tmp/database_dump.json || error "Datenbank Restore fehlgeschlagen"
else
    error "database_dump.json nicht gefunden in $FULL_BACKUP"
fi

# Dokumente
for archive in originals_full.tar.gz archive_full.tar.gz thumbnails_full.tar.gz; do
    if [ -f "$archive" ]; then
        log "Stelle $archive wieder her..."
        docker cp "$archive" "$CONTAINER_NAME:/tmp/"
        docker exec "$CONTAINER_NAME" sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/$archive" || warn "$archive Restore fehlgeschlagen"
    else
        warn "$archive nicht gefunden"
    fi
done

log "Vollbackup wiederhergestellt"

# 2. Inkrementelle Backups anwenden
if [ "$INCREMENTAL_COUNT" -gt 0 ]; then
    log "Schritt 2: Inkrementelle Backups anwenden..."
    
    echo "$INCREMENTAL_BACKUPS" | while read backup_line; do
        backup_dir=$(echo "$backup_line" | cut -d' ' -f2)
        backup_date=$(echo "$backup_line" | cut -d' ' -f1)
        
        log "Wende inkrementelles Backup an: $backup_date"
        cd "$backup_dir"
        
        # Geänderte Dokumente
        if [ -f "incremental_documents.json" ]; then
            log "  - Aktualisiere Dokument-Metadaten..."
            docker cp incremental_documents.json "$CONTAINER_NAME:/tmp/"
            docker exec "$CONTAINER_NAME" python manage.py loaddata /tmp/incremental_documents.json || warn "Incremental documents fehlgeschlagen"
        fi
        
        # Aktuelle Tags/Correspondents
        for entity_file in tags_current.json correspondents_current.json document_types_current.json; do
            if [ -f "$entity_file" ]; then
                log "  - Aktualisiere $entity_file..."
                docker cp "$entity_file" "$CONTAINER_NAME:/tmp/"
                docker exec "$CONTAINER_NAME" python manage.py loaddata "/tmp/$entity_file" || warn "$entity_file Update fehlgeschlagen"
            fi
        done
        
        # Neue/geänderte Dateien
        for inc_archive in originals_incremental.tar.gz archive_incremental.tar.gz thumbnails_incremental.tar.gz; do
            if [ -f "$inc_archive" ]; then
                log "  - Füge neue Dateien hinzu: $inc_archive"
                docker cp "$inc_archive" "$CONTAINER_NAME:/tmp/"
                docker exec "$CONTAINER_NAME" sh -c "cd /usr/src/paperless/media && tar -xzf /tmp/$inc_archive" || warn "$inc_archive Add fehlgeschlagen"
            fi
        done
    done
    
    log "Alle inkrementellen Backups angewendet"
else
    log "Schritt 2: Keine inkrementellen Backups vorhanden"
fi

# 3. Finalisierung
log "Schritt 3: Finalisierung..."

# Permissions korrigieren
log "Korrigiere Permissions..."
docker exec "$CONTAINER_NAME" chown -R paperless:paperless /usr/src/paperless/media || warn "Permission fix fehlgeschlagen"

# Search Index neu aufbauen
log "Baue Search Index neu auf..."
docker exec "$CONTAINER_NAME" python manage.py document_index reindex || warn "Search Index rebuild fehlgeschlagen"

# Cleanup
log "Cleanup temporärer Dateien..."
docker exec "$CONTAINER_NAME" rm -f /tmp/*.json /tmp/*.tar.gz || true

# Container neustarten
if confirm "Container neustarten für optimale Performance?"; then
    log "Starte Container neu..."
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose restart
    else
        docker restart "$CONTAINER_NAME"
    fi
    sleep 30
fi

# Restore-Bericht
log "RESTORE ABGESCHLOSSEN!"
log "====================="
log "Vollbackup: $FULL_BACKUP_DATE"
if [ "$INCREMENTAL_COUNT" -gt 0 ]; then
    log "Inkrementelle Backups: $INCREMENTAL_COUNT angewendet"
fi
log "Ziel-Datum: $RESTORE_DATE"
echo ""
info "Paperless-ngx sollte jetzt mit den wiederhergestellten Daten verfügbar sein"
info "Überprüfe die Anwendung auf Vollständigkeit und Funktionalität"

# Gesundheitscheck
if confirm "Gesundheitscheck durchführen?"; then
    log "Führe Gesundheitscheck durch..."
    
    # Dokumentenanzahl prüfen
    DOC_COUNT=$(docker exec "$CONTAINER_NAME" python manage.py shell -c "from documents.models import Document; print(Document.objects.count())" 2>/dev/null || echo "0")
    info "Dokumentenanzahl: $DOC_COUNT"
    
    # Tags prüfen
    TAG_COUNT=$(docker exec "$CONTAINER_NAME" python manage.py shell -c "from documents.models import Tag; print(Tag.objects.count())" 2>/dev/null || echo "0")
    info "Tags: $TAG_COUNT"
    
    # Correspondents prüfen
    CORR_COUNT=$(docker exec "$CONTAINER_NAME" python manage.py shell -c "from documents.models import Correspondent; print(Correspondent.objects.count())" 2>/dev/null || echo "0")
    info "Correspondents: $CORR_COUNT"
    
    # Fehlende Dateien prüfen
    log "Prüfe auf fehlende Dateien..."
    docker exec "$CONTAINER_NAME" python manage.py shell << 'EOF' || warn "Dateicheck fehlgeschlagen"
from documents.models import Document
import os

missing_files = 0
total_docs = Document.objects.count()

for doc in Document.objects.all():
    if doc.original_file and not os.path.exists(doc.original_file.path):
        print(f"FEHLT: Original für Dokument {doc.id}: {doc.original_file.path}")
        missing_files += 1
    if doc.archive_file and not os.path.exists(doc.archive_file.path):
        print(f"FEHLT: Archiv für Dokument {doc.id}: {doc.archive_file.path}")
        missing_files += 1

print(f"\nGesamt: {total_docs} Dokumente")
print(f"Fehlende Dateien: {missing_files}")
if missing_files == 0:
    print("✅ Alle Dateien sind vorhanden!")
else:
    print("⚠️  Es fehlen Dateien - prüfe Backup-Vollständigkeit")
EOF
fi

log "Smart Restore abgeschlossen!"