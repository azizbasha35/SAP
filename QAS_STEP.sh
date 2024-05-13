#!/bin/bash

# Configuration and Environment Setup
BACKUP_PATH="/backup"
if [ -f "${BACKUP_PATH}/variables.txt" ]; then
    source ${BACKUP_PATH}/variables.txt
else
    echo "Error: variables.txt not found in the backup path."
    exit 1
fi

# Check required variables
if [ -z "$PRD_SID" ] || [ -z "$QAS_SID" ] || [ -z "$EMAIL" ]; then
    echo "Error: PRD_SID, QAS_SID, or EMAIL variable not set in variables.txt."
    exit 1
fi

SAPDATA_PATH="/oracle/${QAS_SID}/sapdata1/temp_1"

# Function to set Oracle environment
function set_oracle_env {
    ORAENV_ASK=NO
    ORACLE_SID=$1
    . oraenv
}

# Function to execute SQL commands
function execute_sql {
    local sql_command="$1"
    echo "$sql_command" | sqlplus -s "/ as sysdba"
}

# Start Script
echo "Starting Oracle DB Refresh Process..."
set_oracle_env $QAS_SID

# Renaming redo log files
echo "Renaming redo log files..."
cd ${BACKUP_PATH}
for file in ${PRD_SID}arch1_*.dbf; do
    mv "$file" "${file/${PRD_SID}/${QAS_SID}}"
done

echo "Setting file permissions..."
chmod 777 ${BACKUP_PATH}/*

echo "Initiating restore..."
brrestore -m full -b bezxbrii.and

# Oracle Recovery Process
execute_sql "
RECOVER DATABASE USING BACKUP CONTROLFILE;
AUTO;
RECOVER DATABASE USING BACKUP CONTROLFILE UNTIL CANCEL;
AUTO;
ALTER DATABASE OPEN RESETLOGS;

-- Configure TEMP files
ALTER DATABASE TEMPFILE '${SAPDATA_PATH}/temp.data1' DROP INCLUDING DATAFILES;
ALTER TABLESPACE PSAPTEMP ADD TEMPFILE '${SAPDATA_PATH}/temp.data1' SIZE 10240M REUSE AUTOEXTEND OFF;

-- Manage Archiving
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
if [ \"\$archiving_enabled\" = \"yes\" ]; then
    ALTER DATABASE ARCHIVELOG;
else
    ALTER DATABASE NOARCHIVELOG;
fi
ALTER DATABASE OPEN;

-- Check Database Status
SELECT INSTANCE_NAME, STATUS, DATABASE_STATUS FROM V\$INSTANCE;
"

# Drop and Create Users
execute_sql "
DROP USER OPS\$${PRD_SID}ADM CASCADE;
DROP USER OPS\$ORA${PRD_SID} CASCADE;
DROP USER OPS\$SAPSERVICE${PRD_SID} CASCADE;

CREATE USER OPS\$ORA${QAS_SID} DEFAULT TABLESPACE SYSTEM TEMPORARY TABLESPACE PSAPTEMP IDENTIFIED EXTERNALLY;
CREATE USER OPS\$${QAS_SID}ADM DEFAULT TABLESPACE SYSTEM TEMPORARY TABLESPACE PSAPTEMP IDENTIFIED EXTERNALLY;
CREATE USER OPS\$SAPSERVICE${QAS_SID} DEFAULT TABLESPACE SYSTEM TEMPORARY TABLESPACE PSAPTEMP IDENTIFIED EXTERNALLY;

GRANT CONNECT, RESOURCE, SAPDBA TO OPS\$${QAS_SID}ADM;
GRANT CONNECT, RESOURCE, SAPDBA TO OPS\$ORA${QAS_SID};
GRANT CONNECT, RESOURCE, SAPDBA TO OPS\$SAPSERVICE${QAS_SID};

CREATE TABLE OPS\$${QAS_SID}ADM.sapuser(userid VARCHAR2(256), passwd VARCHAR2(256));
INSERT INTO OPS\$${QAS_SID}ADM.sapuser VALUES ('SAPNPD-CRYPT', 'V01/0018ZctvSB67Wv2Iy5+rsgn5xHQ=');
CREATE SYNONYM OPS\$SAPSERVICE${QAS_SID}.sapuser FOR OPS\$${QAS_SID}ADM.sapuser;
GRANT SELECT, UPDATE ON OPS\$${QAS_SID}ADM.sapuser TO OPS\$SAPSERVICE${QAS_SID};
"

#!/bin/bash

# Configuration and Environment Setup
BACKUP_PATH="/backup"
if [ -f "${BACKUP_PATH}/variables.txt" ]; then
    source ${BACKUP_PATH}/variables.txt
else
    echo "Error: variables.txt not found in the backup path."
    exit 1
fi

# Check required variables for passwords
if [ -z "$sap_sr3_password" ] || [ -z "$system_password" ]; then
    echo "Error: SAP SR3 or System password not set in variables.txt."
    exit 1
fi

# Change SAP passwords using brtools
echo "Changing SAP SR3 and SYSTEM passwords..."
brconnect -u / -c -f chpass -o SAPSR3 -p $sap_sr3_password -s abap
if [ $? -ne 0 ]; then
    echo "Failed to change SAPSR3 password. Check logs for details."
    exit 1
fi

brconnect -u / -c -f chpass -o SYSTEM -p $system_password -s abap
if [ $? -ne 0 ]; then
    echo "Failed to change SYSTEM password. Check logs for details."
    exit 1
fi

echo "SAP passwords updated successfully."

# Check SAP connection and start SAP
echo "Checking SAP database connection..."
R3trans -d > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "DB Connection OK. Starting SAP..."
    startsap
    echo "SAP started successfully."
else
    echo "Error: SAP database connection failed. Check the R3trans log for details."
    exit 1
fi

# Monitor SAP system start status
echo "Monitoring SAP system status until all components are GREEN..."

# Define a function to check if all SAP components are GREEN
function all_components_green {
    statuses=$(sapcontrol -nr 00 -function GetProcessList | grep -Eo 'GREEN|GRAY|YELLOW|RED')
    if [[ "$statuses" == "" ]]; then
        return 1 # Return 1 if sapcontrol fails to get any status
    fi
    for status in $statuses; do
        if [ "$status" != "GREEN" ]; then
            return 1 # Return 1 if any component is not GREEN
        fi
    done
    return 0 # Return 0 only if all components are GREEN
}

# Continue to check every 30 seconds until all components report GREEN
until all_components_green; do
    echo "Not all components are GREEN, rechecking in 30 seconds..."
    sleep 30
done

echo "All SAP components are GREEN. System is fully operational."


# Completion Message
echo "ORACLE DB Refresh has been successfully Completed."
echo "Sending notification email to ${EMAIL}."
echo "ORACLE DB Refresh has been successfully Completed" | mail -s "DB Refresh Notification" ${EMAIL}
