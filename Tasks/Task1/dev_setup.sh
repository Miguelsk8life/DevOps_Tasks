#!/bin/bash


LOG_FILE="setup_dev_group.log"


exec > >(tee -i "$LOG_FILE") 2>&1

echo "=== Starting DevOps setup script ==="
echo "Date and time: $(date)"
echo "------------------------------------------------"


DIR_PATH=""

while getopts "d:" opt; do
  case ${opt} in
    d )
      DIR_PATH=$OPTARG
      ;;
    \? )
      echo "Invalid usage. Syntax: $0 [-d /path/to/directory]"
      exit 1
      ;;
  esac
done


if [ -z "$DIR_PATH" ]; then
    read -p "Please enter the base path for the work directories (-d): " DIR_PATH
fi


if [ -z "$DIR_PATH" ]; then
    echo "Error: The directory path cannot be empty."
    exit 1
fi


mkdir -p "$DIR_PATH"


if ! getent group dev >/dev/null; then
    echo "[+] Creating the 'dev' group..."
    groupadd dev
else
    echo "[*] The 'dev' group already exists."
fi


SUDOERS_FILE="/etc/sudoers.d/dev_group"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "[+] Configuring sudo access without a password for the 'dev' group..."
    echo "%dev ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"
else
    echo "[*] The sudo configuration for 'dev' already exists."
fi


echo "[+] Processing non-system users..."


MIN_UID=$(awk '/^UID_MIN/ {print $2}' /etc/login.defs || echo 1000)
MAX_UID=$(awk '/^UID_MAX/ {print $2}' /etc/login.defs || echo 60000)


while IFS=: read -r username password uid gid info home shell; do
    if [ "$uid" -ge "$MIN_UID" ] && [ "$uid" -le "$MAX_UID" ] && [ "$username" != "nobody" ]; then

        echo "--------------------------------------------"
        echo "Processing user: $username (UID: $uid)"


        usermod -aG dev "$username"
        echo "  -> Added to the 'dev' group"


        USER_DIR="${DIR_PATH}/${username}_workdir"


        mkdir -p "$USER_DIR"
        echo "  -> Directory created: $USER_DIR"

        PRIMARY_GROUP=$(getent group "$gid" | cut -d: -f1)
        chown "${username}:${PRIMARY_GROUP}" "$USER_DIR"


        chmod 660 "$USER_DIR"
        echo "  -> Initial permissions set to 660 and owner established."


        if command -v setfacl >/dev/null 2>&1; then
            setfacl -m g:dev:r "$USER_DIR"
            echo "  -> Read permission for the 'dev' group applied via ACL."
        else
            echo "  [!] Warning: 'setfacl' is not installed. Could not apply specific read access for 'dev' while maintaining strict 660."
        fi

    fi
done < /etc/passwd

echo "--------------------------------------------"
echo "=== Task completed successfully ==="
echo "You can review the complete log at: $LOG_FILE"
