#!/bin/bash
# Get helper file for workstation
USER_HOME=$(cat /etc/passwd | grep ^U | cut -d: -f6)
USER=$(cat /etc/passwd | grep ^U | cut -d: -f1)
cp ./cli-helper-1518.adoc $USER_HOME/cli-helper-1518.adoc
cp ./cli-helper-1518.html $USER_HOME/cli-helper-1518.html
chown $USER $USER_HOME/cli-helper-1518*
chmod 644 $USER_HOME/cli-helper-1518*

## Configure html cli helper file as the default Firefox home page
PROFILE_DIR=$(find $USER_HOME/.mozilla/firefox -type d -name "*.default*" | head -n 1)
if [ -z "$PROFILE_DIR" ]; then
    echo "No Firefox profile found. Starting Firefox to create one..."
    sudo su - $USER -c "firefox --headless &"
    sleep 10
    pkill -f firefox
fi

# Search for the prefs.js file in the user's home directory
PREFS_PATH=$(find $USER_HOME -type f -name "prefs.js" | grep ".mozilla/firefox" | head -n 1)

# Check if the prefs.js file was found
if [ -z "$PREFS_PATH" ]; then
    echo "prefs.js file not found in the home directory."
    exit 1
fi

# Update profiles.ini to ensure the correct profile is used
PROFILES_INI="$USER_HOME/.mozilla/firefox/profiles.ini"
if [ -f "$PROFILES_INI" ]; then
    echo "Updating profiles.ini to set the correct profile as default."
    PROFILE_DIR=$(find $USER_HOME/.mozilla/firefox -type d -name "*.default*" | head -n 1)
    PROFILE_NAME=$(basename "$PROFILE_DIR")
    cat <<EOF > "$PROFILES_INI"
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default
IsRelative=1
Path=$PROFILE_NAME
Default=1
EOF
fi

## Define the path to the local HTML file
HTML_FILE_PATH="$USER_HOME/cli-helper-1518.html"

## Convert the file path to a URL format
FILE_URL="file://$HTML_FILE_PATH"

## Specify the second URL to open in a new tab
SECOND_URL="https://ceph-node1:8443"

## Backup the current prefs.js file
cp "$PREFS_PATH" "$PREFS_PATH.bak"

## Check if the user.js file exists in the same directory as prefs.js and create it if not
USER_JS_PATH=$(dirname "$PREFS_PATH")/user.js
if [ ! -f "$USER_JS_PATH" ]; then
    touch "$USER_JS_PATH"
    chmod 644 $USER_JS_PATH
    chown $USER:$USER $USER_JS_PATH
fi

## Add the local file URL and the second URL to the startup pages (home pages) in user.js
echo 'user_pref("browser.startup.homepage", "'$FILE_URL'|'$SECOND_URL'");' >> "$USER_JS_PATH"
echo "Firefox will open with $FILE_URL and $SECOND_URL on startup."

## SSL Certificate Section

# Define the dashboard URL
DASHBOARD_URL="ceph-node1:8443"

echo "SSL certificate added to the trusted store. Configuration complete."

# Extract the SSL certificate
#CERT_DIR="$USER_HOME/.certs"
#mkdir -p $CERT_DIR
#CERT_FILE="$CERT_DIR/dashboard-cert.pem"
#echo "Fetching SSL certificate from $DASHBOARD_URL..."
#echo -n | openssl s_client -connect $DASHBOARD_URL -servername $DASHBOARD_URL | \
#    sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > $CERT_FILE

#echo "Adding SSL certificate to the trusted store..."
#sudo cp $CERT_FILE /etc/pki/ca-trust/source/anchors/
#sudo update-ca-trust

# Import the certificate into Firefox's certificate store
#CERT_DB_DIR="$PROFILE_DIR"
#echo "Importing the SSL certificate into Firefox's certificate store..."
#dnf install nss-tools -y
#pkill firefox
#certutil -D -n "Ceph Dashboard Certificate" -d sql:$CERT_DB_DIR
#certutil -A -n "Ceph Dashboard Certificate" -t "C,," -i $CERT_FILE -d sql:$CERT_DB_DIR
#echo "SSL certificate imported into Firefox's certificate store. Configuration complete."

# Verify that the certificate has been added
#certutil -L -d sql:$CERT_DB_DIR


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
DNS.6 = ceph-node1
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

# SCP the certificates to the remote Ceph node
echo "Copying certificates to ceph-node1..."
ssh ceph-node1 "mkdir /root/ssl-cert/"
scp ceph-node3.crt ceph-node3.key rootCA.pem ceph-node1:/root/ssl-cert/

# Use the generated certificates for the Ceph Dashboard
echo "Setting up Ceph Dashboard to use the generated SSL certificate..."
ssh ceph-node1 sudo ceph dashboard set-ssl-certificate -i /root/ssl-cert/ceph-node3.crt
ssh ceph-node1 sudo ceph dashboard set-ssl-certificate-key -i /root/ssl-cert/ceph-node3.key
ssh ceph-node1 sudo ceph dashboard set-rgw-api-ssl-verify False

# Restart the Ceph MGR to apply the changes
echo "Restarting Ceph Manager to apply the SSL certificate changes..."
ssh ceph-node1 "podman restart \$(podman ps | grep mgr | awk '{print \$1}')"
sleep 10

# Define the paths to the certificate and CA
CERT_DB_DIR="$PROFILE_DIR"
CERT_FILE="$USER/ceph-node3.crt"
ROOT_CA_FILE="$USER/rootCA.pem"

# Import the new SSL certificate into Firefox's certificate store
echo "Importing the SSL certificate into Firefox's certificate store..."
sudo -u $USER certutil -D -n "Ceph Dashboard Certificate" -d sql:$CERT_DB_DIR
sudo -u $USER certutil -A -n "Ceph Dashboard Certificate" -t "C,," -i $CERT_FILE -d sql:$CERT_DB_DIR

# Import the Root CA into Firefox's certificate store
echo "Importing the Root CA into Firefox's certificate store..."
sudo -u $USER certutil -D -n "Ceph Dashboard Root CA" -d sql:$CERT_DB_DIR
sudo -u $USER certutil -A -n "Ceph Dashboard Root CA" -t "C,," -i $ROOT_CA_FILE -d sql:$CERT_DB_DIR

# Verify that the certificate and Root CA have been added
sudo -u $USER certutil -L -d sql:$CERT_DB_DIR

echo "Firefox certificate import complete."

