#!/bin/bash
# Migration script to move existing flat transcripts into dated directory structure
# Usage: ./migrate_transcripts.sh [--dry-run]

TRANSCRIPT_DIR="$(dirname "$0")/transcripts"
DRY_RUN=false

if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE - No changes will be made ==="
fi

# Count files to migrate
count=0

for file in "$TRANSCRIPT_DIR"/*.md; do
    # Skip if no files match or if it's the gitkeep
    [[ -e "$file" ]] || continue
    [[ "$(basename "$file")" == ".gitkeep" ]] && continue

    filename=$(basename "$file")

    # Parse date and time from filename: YYYY-MM-DD_HH-MM-SS.md
    if [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2}-[0-9]{2}-[0-9]{2})\.md$ ]]; then
        date_part="${BASH_REMATCH[1]}"
        time_part="${BASH_REMATCH[2]}"

        target_dir="$TRANSCRIPT_DIR/$date_part/$time_part"
        target_file="$target_dir/transcript.md"

        if $DRY_RUN; then
            echo "Would move: $file -> $target_file"
        else
            mkdir -p "$target_dir"
            mv "$file" "$target_file"
            echo "Migrated: $filename -> $date_part/$time_part/transcript.md"
        fi
        ((count++))
    else
        echo "Skipping (unexpected format): $filename"
    fi
done

echo ""
echo "=== Migration complete: $count files processed ==="
