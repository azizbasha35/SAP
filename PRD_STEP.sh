#!/bin/bash

# Source root specific environment variables
if [ "$(id -u)" -eq 0 ]; then
    source /backup/export_var.sh
else
    echo "This script must be run as root."
    exit 1
fi

# Define logging function
log() {
    local current_date=$(date '+%Y-%m-%d')
    local log_file="$backup_path_sap/PRD_${current_date}.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}

# Function to send email
send_email() {
    local recipient="$1"
    local subject="$2"
    local body="$3"
    echo "$body" | mail -s "$subject" "$recipient"
}

# Error handling function
handle_error() {
    local error_code="$1"
    local error_message="$2"
    log "$error_message"
    send_email "admin@example.com" "Script Error: $error_code" "$error_message"
    exit "$error_code"
}

# Debugging: Print environment variables to verify they're set
echo "Debug: ORASID_PRD = $orasid_prd"
echo "Debug: Backup Path SAP = $backup_path_sap"

# Switch user to orasid_prd and execute setenv_var.sh
echo "Switching user to $orasid_prd and executing setenv_var.sh..."
sudo su - "$orasid_prd" -c "source /backup/setenv_var.sh"

# Ensure the backup directory exists
if [ ! -d "$backup_path_sap" ]; then
    log "Backup directory $backup_path_sap does not exist, creating it."
    mkdir -p "$backup_path_sap"
    if [ $? -ne 0 ]; then
        log "Failed to create backup directory. Check permissions."
        handle_error "2" "Failed to create backup directory. Check permissions."
    fi
fi

# Login with ORASID_PRD and execute SQL commands
log "Logging in as $orasid_prd..."
su_output=$(sudo su - "$orasid_prd" -c "
    sqlplus -s / as sysdba <<EOF
    alter database backup controlfile to trace;
    show parameter user_dump_dest;
    exit;
EOF
")
trc_file_path=$(echo "$su_output" | grep -oP 'user_dump_dest.*' | awk '{print $3}')

# Assuming $backup_path_sap is the directory containing .trc files
trc_file_path=$(find "$backup_path_sap" -type f -name '*.trc' -print0 | xargs -0 ls -t | head -n 1)

# Handle trace file path extraction and editing
# Assuming the latest .trc file needs to be processed
trc_file_path=$(find "/oracle/PRD/19/rdbms/log" -type f -name '*.trc' -print0 | xargs -0 ls -t | head -n 1)

if [ -f "$trc_file_path" ]; then
    control_file_path="$backup_path_sap/control_${orasid_qas}.sql"
    log "Processing .trc file for necessary edits..."
    sed -n '/CREATE CONTROLFILE/,/RESETLOGS/p' "$trc_file_path" | sed 's/REUSE/SET/' | sed "s/$orasid_prd/$orasid_qas/g" > "$control_file_path"
else
    log "Failed to locate the trace file path. Check output and permissions."
    handle_error "6" "Failed to locate the trace file path. Check output and permissions."
fi

# Start online backup
log "Starting online backup of PRD system..."
sudo su - "$orasid_prd" -c "brbackup -p initPRD.sap -d disk -t online_cons -c force -u /"
if [ $? -ne 0 ]; then
    log "Backup failed. Please check system logs."
    handle_error "3" "Backup failed. Please check system logs."
fi

# Edit backup files
log "Editing backup and log files..."
sed -i "s/$PRD_SID/$QAS_SID/g" "$backup_path_sap"/*.and

# Additional operations like copying and modifying trace files, and executing control file script
cp "$trc_file_path" "$backup_path/latest_trace.trc"
sed -n '/CREATE CONTROLFILE/,$p' "$backup_path/latest_trace.trc" | sed '/^RESETLOGS/q' | sed 's/REUSE/SET/g' | sed "s/$orasid_prd/$orasid_qas/g" > "$backup_path/control_${orasid_qas}.sql"
su - "$orasid_qas" -c "sqlplus / as sysdba @/backup/control_${orasid_qas}.sql"

log "SCRIPT EXECUTION COMPLETED."
