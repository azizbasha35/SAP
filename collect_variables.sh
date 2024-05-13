#!/bin/bash
# FUNCTION TO DISPLAY ERROR MESSAGE AND PROMPT USER TO RE-EXECUTE
handle_error() {
    echo "AN ERROR OCCURRED: $1"
    read -rp "WOULD YOU LIKE TO RE-EXECUTE THE SCRIPT? (YES/NO): " choice
    case "$choice" in
        [Yy]|[Yy][Ee][Ss])
            exec "$0" "$@" ;;
        *)
            echo "EXITING SCRIPT." ;;
    esac
    exit 1
}

# FUNCTION TO PROMPT USER FOR INPUT WITH A GIVEN MESSAGE AND SET AS ENVIRONMENT VARIABLE
prompt_and_set_env() {
    local var_name=$1
    local input
    read -rp "$2: " input
    export "$var_name"="$input"
}

# DISPLAY INSTRUCTIONS TO THE USER
echo "***********************************************************************"
echo "PLEASE ENTER THE FOLLOWING DETAILS:"
echo "***********************************************************************"

# PROMPT THE USER FOR SYSTEM DETAILS AND SET AS ENVIRONMENT VARIABLES
prompt_and_set_env PRD_SID "ENTER PRD_SID"
prompt_and_set_env QAS_SID "ENTER QAS_SID"
prompt_and_set_env PRD_IP_ADDRESS "ENTER PRD_IP_ADDRESS"
prompt_and_set_env QAS_IP_ADDRESS "ENTER QAS_IP_ADDRESS"

echo "***********************************************************************"

# REQUEST FOR PASSWORDS
prompt_and_set_env PRD_SAPSR3_PASSWORD "ENTER PRD SAPSR3 PASSWORD"
prompt_and_set_env PRD_SYSTEM_PASSWORD "ENTER PRD SYSTEM PASSWORD"
prompt_and_set_env QAS_SAPSR3_PASSWORD "ENTER QAS SAPSR3 PASSWORD"
prompt_and_set_env QAS_SYSTEM_PASSWORD "ENTER QAS SYSTEM PASSWORD"

echo "***********************************************************************"

# PROMPT FOR ENABLING ARCHIVING IN THE TARGET SYSTEM
read -rp "ENABLE ARCHIVING IN THE QAS SYSTEM? (YES/NO): " enable_archiving
case "$enable_archiving" in
    [Yy]|[Yy][Ee][Ss]) archiving_enabled=true ;;
    [Nn]|[Nn][Oo]) archiving_enabled=false ;;
    *) handle_error "INVALID INPUT FOR ARCHIVING OPTION." ;;
esac

echo "***********************************************************************"

# REQUEST FOR EMAIL ADDRESS TO SEND STATUS REPORT
prompt_and_set_env email_address "ENTER YOUR EMAIL ADDRESS TO RECEIVE STATUS REPORT"

echo "***********************************************************************"

# SET DEFAULT VALUE FOR BACKUP_PATH_SAP
prompt_and_set_env backup_path_sap "ENTER THE BACKUP PATH (/BACKUP IS DEFAULT)"

echo "***********************************************************************"

# CHECK IF $BACKUP_PATH_SAP IS AN NFS MOUNT POINT
# FUNCTION TO CHECK IF A DIRECTORY IS AN NFS MOUNT POINT
check_nfs_mount() {
    if mountpoint -q -t nfs "$backup_path_sap"; then
        echo "BACKUP PATH IS AN NFS MOUNT POINT."
    else
        echo "WARNING: BACKUP PATH IS NOT AN NFS MOUNT POINT."
    fi
}

echo "***********************************************************************"

# ENSURE THE BACKUP DIRECTORY EXISTS
if [ ! -d "$backup_path_sap" ]; then
    echo "THE BACKUP DIRECTORY DOES NOT EXIST. ATTEMPTING TO CREATE IT..."
    if mkdir -p "$backup_path_sap"; then
        echo "BACKUP DIRECTORY CREATED SUCCESSFULLY."
    else
        handle_error "FAILED TO CREATE BACKUP DIRECTORY. PLEASE CREATE IT MANUALLY."
    fi
fi

echo "***********************************************************************"

# STORE THE VARIABLES IN A FILE
echo "STORING YOUR DETAILS SECURELY..."
cat > "$backup_path_sap/variables.txt" << EOF
PRD_SID="$PRD_SID"
QAS_SID="$QAS_SID"
PRD_IP_ADDRESS="$PRD_IP_ADDRESS"
QAS_IP_ADDRESS="$QAS_IP_ADDRESS"
PRD_SAPSR3_PASSWORD="$PRD_SAPSR3_PASSWORD"
PRD_SYSTEM_PASSWORD="$PRD_SYSTEM_PASSWORD"
QAS_SAPSR3_PASSWORD="$QAS_SAPSR3_PASSWORD"
QAS_SYSTEM_PASSWORD="$QAS_SYSTEM_PASSWORD"
archiving_enabled="$archiving_enabled"
email_address="$email_address"
backup_path_sap="$backup_path_sap"
EOF

echo "YOUR DETAILS HAVE BEEN STORED SUCCESSFULLY."

echo "***********************************************************************"

# CREATE export_var.sh FILE
echo "CREATING export_vars.sh FILE..."
cat > "$backup_path_sap/export_var.sh" << EOF
#!/bin/bash
EOF
# EXPORT EACH ENVIRONMENT VARIABLE INDIVIDUALLY WITHOUT DOUBLE QUOTES AROUND VALUES
for var in PRD_SID QAS_SID PRD_IP_ADDRESS QAS_IP_ADDRESS PRD_SAPSR3_PASSWORD PRD_SYSTEM_PASSWORD QAS_SAPSR3_PASSWORD QAS_SYSTEM_PASSWORD archiving_enabled email_address backup_path_sap; do
    echo "export $var=$(eval echo \$$var)" >> "$backup_path_sap/export_var.sh"
done
# EXPORT SIDADM_PRD AND SIDADM_QAS VARIABLES
echo "export sidadm_prd=${PRD_SID,,}adm" >> "$backup_path_sap/export_var.sh"
echo "export sidadm_qas=${QAS_SID,,}adm" >> "$backup_path_sap/export_var.sh"
echo "export orasid_prd=ora${PRD_SID,,}" >> "$backup_path_sap/export_var.sh"
echo "export orasid_qas=ora${QAS_SID,,}" >> "$backup_path_sap/export_var.sh"

chmod +x "$backup_path_sap/export_var.sh"
echo "export_var.sh FILE CREATED."

echo "***********************************************************************"

# CREATE setenv_var.sh FILE
echo "CREATING setenv_var.sh FILE..."
cat > "$backup_path_sap/setenv_var.sh" << EOF
#!/bin/bash
EOF
# EXPORT EACH ENVIRONMENT VARIABLE INDIVIDUALLY WITHOUT DOUBLE QUOTES AROUND VALUES
for var in PRD_SID QAS_SID PRD_IP_ADDRESS QAS_IP_ADDRESS PRD_SAPSR3_PASSWORD PRD_SYSTEM_PASSWORD QAS_SAPSR3_PASSWORD QAS_SYSTEM_PASSWORD archiving_enabled email_address backup_path_sap; do
    echo "setenv $var $(eval echo \$$var)" >> "$backup_path_sap/setenv_var.sh"
done
# EXPORT SIDADM_PRD AND SIDADM_QAS VARIABLES
echo "setenv sidadm_prd ${PRD_SID,,}adm" >> "$backup_path_sap/setenv_var.sh"
echo "setenv sidadm_qas ${QAS_SID,,}adm" >> "$backup_path_sap/setenv_var.sh"
echo "setenv orasid_prd ora${PRD_SID,,}" >> "$backup_path_sap/setenv_var.sh"
echo "setenv orasid_qas ora${QAS_SID,,}" >> "$backup_path_sap/setenv_var.sh"

chmod +x "$backup_path_sap/setenv_var.sh"
echo "setenv_var.sh FILE CREATED."
echo "***********************************************************************"