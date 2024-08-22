#!/bin/bash
# Get helper file for workstation
USER_HOME=$(cat /etc/passwd | grep ^U | cut -d: -f6)
wget https://gist.githubusercontent.com/likid0/f034a5e8472b1ed38370463e8b06cc93/raw/9f49c677390493b2e8bdc4e768b563fcf13f2326/helperfile.adoc -O $USER_HOME/cli-helper-1518.adoc
chmod 644 $USER_HOME/cli-helper-1518.adoc

PROFILE_DIR=$(find $HOME/.mozilla/firefox -type d -name "*.default*" | head -n 1)

if [ -z "$PROFILE_DIR" ]; then
    echo "No Firefox profile found. Starting Firefox to create one..."
    firefox & sleep 5 && pkill firefox
fi

# Search for the prefs.js file in the user's home directory
PREFS_PATH=$(find $HOME -type f -name "prefs.js" | grep ".mozilla/firefox" | head -n 1)

# Check if the prefs.js file was found
if [ -z "$PREFS_PATH" ]; then
    echo "prefs.js file not found in the home directory."
    exit 1
fi

# Define the path to the local HTML file
HTML_FILE_PATH="$HOME/cli-helper-1518.html"

# Convert the file path to a URL format
FILE_URL="file://$HTML_FILE_PATH"

# Backup the current prefs.js file
cp "$PREFS_PATH" "$PREFS_PATH.bak"

# Check if the user.js file exists in the same directory as prefs.js and create it if not
USER_JS_PATH=$(dirname "$PREFS_PATH")/user.js
if [ ! -f "$USER_JS_PATH" ]; then
    touch "$USER_JS_PATH"
fi

# Add the local file URL to the startup pages (home page) in user.js
echo 'user_pref("browser.startup.homepage", "'$FILE_URL'");' >> "$USER_JS_PATH"

echo "Firefox will open with $FILE_URL on startup."


# Create Self-Signed Certs for LAB

SSL_DIR="/root/ssl-cert"
mkdir -p $SSL_DIR
cd $SSL_DIR

echo "Generating root CA key..."
openssl genrsa -out rootCA.key 2048
if [ $? -ne 0 ]; then
  echo "Error generating root CA key."
  exit 1
fi

echo "Generating root CA certificate..."
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 365 -out rootCA.pem -subj "/CN=ceph-workstation"
if [ $? -ne 0 ]; then
  echo "Error generating root CA certificate."
  exit 1
fi

echo "Generating node key and CSR..."
openssl req -new -newkey rsa:2048 -sha256 -nodes -keyout ceph-node3.key -subj "/CN=ceph-node3" -out ceph-node3.csr
if [ $? -ne 0 ]; then
  echo "Error generating node key and CSR."
  exit 1
fi

echo "Creating v3.ext file..."
cat > v3.ext <<EOL
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ceph-node3
DNS.2 = ceph-node3*
DNS.3 = *.example.com
DNS.4 = ceph-node4
DNS.5 = ceph-node2
EOL
if [ $? -ne 0 ]; then
  echo "Error creating v3.ext file."
  exit 1
fi

echo "Generating node certificate..."
openssl x509 -req -in ceph-node3.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out ceph-node3.crt -days 365 -sha256 -extfile v3.ext
if [ $? -ne 0 ]; then
  echo "Error generating node certificate."
  exit 1
fi

echo "Combining key, certificate, and root CA into ceph-node3.pem..."
cat ceph-node3.key ceph-node3.crt rootCA.pem > ceph-node3.pem
if [ $? -ne 0 ]; then
  echo "Error creating ceph-node3.pem."
  exit 1
fi

echo "Copying root CA to trusted anchors..."
cp -f rootCA.pem /etc/pki/ca-trust/source/anchors/
if [ $? -ne 0 ]; then
  echo "Error copying root CA to trusted anchors."
  exit 1
fi

echo "Updating CA trust..."
update-ca-trust
if [ $? -ne 0 ]; then
  echo "Error updating CA trust."
  exit 1
fi

USER_HOME=$(cat /etc/passwd | grep ^U | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
  echo "User with UID 1000 not found."
  exit 1
fi

echo "Copying ceph-node3.pem and rootCA.pem to $USER_HOME with 644 permissions..."
cp ceph-node3.pem $USER_HOME/
cp rootCA.pem $USER_HOME/
chmod 644 $USER_HOME/rootCA.pem
if [ $? -ne 0 ]; then
  echo "Error copying ceph-node3.pem to $USER_HOME."
  exit 1
fi

chmod 644 $USER_HOME/ceph-node3.pem
if [ $? -ne 0 ]; then
  echo "Error setting permissions on $USER_HOME/ceph-node3.pem."
  exit 1
fi

echo "SSL certificate generation and configuration completed successfully."

# Disable ssl check for the Dashboard for the Self-Signed
ssh ceph-node1 sudo ceph dashboard set-rgw-api-ssl-verify False
