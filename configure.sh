#!/usr/bin/env sh

# Default values
REALM_NAME="${REALM_NAME-EXAMPLE.COM}"
DOMAIN_NAME="${DOMAIN_NAME-example.com}"
KADMIN_PASS="${KADMIN_PASS-Secure_Password}"
MASTER_PASS="${MASTER_PASS-Master_Password}"

# Function: Generate keytab filename from principal name
# Removes realm part and converts slashes to underscores
get_keytab_name() {
    local principal="$1"
    # Remove realm part if exists
    principal=$(echo "$principal" | sed "s/@${REALM_NAME}//")
    # Convert slashes to underscores
    echo "$principal" | sed 's/\//_/g'
}

# Function: Check if principal already exists
# Adds realm if not present in principal name
principal_exists() {
    local principal="$1"
    # Add realm if not present
    if ! echo "$principal" | grep -q "@"; then
        principal="${principal}@${REALM_NAME}"
    fi
    kadmin.local -q "listprincs" | grep -q "^$principal$"
    return $?
}

# Function: Check if keytab file exists
keytab_exists() {
    local keytab_name=$(get_keytab_name "$1")
    [ -f "/keytabs/${keytab_name}.keytab" ]
    return $?
}

# Function: Create principal and its keytab file
# Handles both creation and verification
create_principal_and_keytab() {
    local principal="$1"
    local keytab_name=$(get_keytab_name "$principal")

    # Add realm if not present in principal name
    if ! echo "$principal" | grep -q "@"; then
        principal="${principal}@${REALM_NAME}"
    fi

    echo "Processing principal: $principal"
    echo "Keytab name will be: ${keytab_name}.keytab"

    # Create principal if it doesn't exist
    if ! principal_exists "$principal"; then
        echo "Creating principal: $principal"
        kadmin.local -q "addprinc -randkey $principal"
    else
        echo "Principal $principal already exists"
    fi

    # Create keytab if it doesn't exist
    if ! keytab_exists "$principal"; then
        echo "Creating keytab for: $principal"
        kadmin.local -q "ktadd -k /keytabs/${keytab_name}.keytab $principal"
        chmod 666 "/keytabs/${keytab_name}.keytab"
        echo "Created keytab: /keytabs/${keytab_name}.keytab"
    else
        echo "Keytab for $principal already exists"
    fi
}

# Copying krb5 conf file
cat > /etc/krb5.conf << EOL
[logging]
    default = FILE:/var/log/krb5libs.log
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmind.log

[libdefaults]
    dns_lookup_realm = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    default_realm = ${REALM_NAME}

[realms]
    ${REALM_NAME} = {
        kdc = localhost
        admin_server = localhost
    }

[domain_realm]
    .${DOMAIN_NAME} = ${REALM_NAME}
    ${DOMAIN_NAME} = ${REALM_NAME}
EOL

# Creating initial database
kdb5_util -r ${REALM_NAME} create -s << EOL
${MASTER_PASS}
${MASTER_PASS}
EOL

# Creating admin principal
kadmin.local -q "addprinc root/admin@${REALM_NAME}" << EOL
${KADMIN_PASS}
${KADMIN_PASS}
EOL

# Create and set permissions for keytabs directory
mkdir -p /keytabs
chmod 755 /keytabs

# Process each principal from the comma-separated list
echo "Starting principal creation..."
echo "$PRINCIPALS" | tr ',' '\n' | while read -r principal
do
    if [ -n "$principal" ]; then
        create_principal_and_keytab "$principal"
    fi
done

# Display created keytab files and their contents
echo "Created keytab files:"
ls -l /keytabs/
for keytab in /keytabs/*.keytab; do
    if [ -f "$keytab" ]; then
        echo "Contents of $keytab:"
        klist -kt "$keytab"
    fi
done

echo "Keytab creation completed"

# Start services
kadmind
krb5kdc

tail -f /var/log/krb5kdc.log
