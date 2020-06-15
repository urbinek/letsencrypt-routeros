#!/bin/bash
set -e

CONFIG_FILE=/etc/letsencrypt-routeros/letsencrypt-routeros.settings

function echo_date {
    echo -e "$(date +%F\ %T):\t$1"
}

case "$#" in
    "0")
        if [ -f $CONFIG_FILE ]; then
            source $CONFIG_FILE
            if [[ -z $ROUTEROS_USER ]] || [[ -z $ROUTEROS_HOST ]] || [[ -z $ROUTEROS_SSH_PORT ]] || [[ -z $ROUTEROS_PRIVATE_KEY ]] || [[ -z $DOMAIN ]]; then
                echo_date "Some parameters are missing. Please check config file: $CONFIG_FILE"
                echo_date "Current content:"
                echo_date "ROUTEROS_USER=$ROUTEROS_USER"
                echo_date "ROUTEROS_HOST=$ROUTEROS_HOST"
                echo_date "ROUTEROS_SSH_PORT=$ROUTEROS_SSH_PORT"
                echo_date "ROUTEROS_PRIVATE_KEY=$ROUTEROS_PRIVATE_KEY"
                echo_date "DOMAIN=$DOMAIN"
                exit
            fi
        else
            echo_date "Missing config file! Ensure that $CONFIG_FILE is configured."
            exit 1
        fi
    ;;
    "6")
        ROUTEROS_USER=$1
        ROUTEROS_HOST=$2
        ROUTEROS_SSH_PORT=$3
        ROUTEROS_PRIVATE_KEY=$4
        DOMAIN=$5
    ;;
    *)
        echo_date "ERROR! This script require require either in-line parameters or $CONFIG_FILE"
        echo_date ""
        echo_date "Exampla usage:"
        echo_date "$0 [RouterOS User] [RouterOS Host] [SSH Port] [SSH Private Key] [Domain]"
        echo_date "$0"
        echo_date ""
        echo_date "Example content of $CONFIG_FILE:"
        echo_date "ROUTEROS_USER=admin-ssh"
        echo_date "ROUTEROS_HOST=192.168.88.1"
        echo_date "ROUTEROS_SSH_PORT=22"
        echo_date "ROUTEROS_PRIVATE_KEY=/opt/letsencrypt-routeros/id_dsa"
        echo_date "DOMAIN=domain.local"
        exit 10
esac



CERTIFICATE=/etc/letsencrypt/live/$DOMAIN/cert.pem
KEY=/etc/letsencrypt/live/$DOMAIN/privkey.pem

# Creating alias for RouterOS command
routeros="ssh -i $ROUTEROS_PRIVATE_KEY $ROUTEROS_USER@$ROUTEROS_HOST -p $ROUTEROS_SSH_PORT"

echo_date "Checking connection to RouterOS..."
if [[ `$routeros /system resource print` ]]; then
    $routeros /system resource print | grep "board-name:\|factory-software:\|cpu:"
else
    echo_date "    Error in: $routeros"
    echo_date "More info: https://wiki.mikrotik.com/wiki/Use_SSH_to_execute_commands_(DSA_key_login)"
    exit 1
fi

if [ ! -f $CERTIFICATE ] && [ ! -f $KEY ]; then
    echo_date "File(s) not found:"
    echo_date "$CERTIFICATE"
    echo_date "$KEY"
    echo_date ""
    echo_date "Please use CertBot Let's Encrypt e.g.:"
    echo_date "certbot certonly --preferred-challenges=dns --manual -d $DOMAIN --manual-public-ip-logging-ok"
    echo_date "or (for wildcard certificate):"
    echo_date "certbot certonly --preferred-challenges=dns --manual -d *.$DOMAIN --manual-public-ip-logging-ok --server https://acme-v02.api.letsencrypt.org/directory"
    echo_date ""
    echo_date "and follow instructions from CertBot    "
    exit 1
fi

echo_date ""
echo_date "Removing previous cert configuraton..."
$routeros /certificate remove [find name=$DOMAIN.pem_0]
$routeros /file remove $DOMAIN.pem > /dev/null || echo_date " - $DOMAIN.pem already removed!"
$routeros /file remove $DOMAIN.key > /dev/null || echo_date " - $DOMAIN.key already removed!"

echo_date ""
echo_date "Upload new certificate and key pair to RouterOS..."
scp -q -P $ROUTEROS_SSH_PORT -i "$ROUTEROS_PRIVATE_KEY" "$CERTIFICATE" "$ROUTEROS_USER"@"$ROUTEROS_HOST":"$DOMAIN.pem"
scp -q -P $ROUTEROS_SSH_PORT -i "$ROUTEROS_PRIVATE_KEY" "$KEY" "$ROUTEROS_USER"@"$ROUTEROS_HOST":"$DOMAIN.key"

echo_date ""
echo_date "Importing..."
echo_date " - /certificate import file-name=$DOMAIN.pem passphrase=\"\""
$routeros /certificate import file-name=$DOMAIN.pem passphrase=\"\" || echo_date "Failed!"
echo_date " - /certificate import file-name=$DOMAIN.pem passphrase=\"\""
$routeros /certificate import file-name=$DOMAIN.key passphrase=\"\" || echo_date "Failed!"

echo_date ""
echo_date "Setup Certificates..."
echo_date " - SSTP Server:  /interface sstp-server server set certificate=$DOMAIN.pem_0"
$routeros /interface sstp-server server set certificate=$DOMAIN.pem_0

echo_date " - OpenVPN Server: /interface ovpn-server server set certificate==$DOMAIN.pem_0"
$routeros /interface ovpn-server server set certificate==$DOMAIN.pem_0

echo_date " - WebUI Server: /ip service set www-ssl certificate=$DOMAIN.pem_0"
$routeros /ip service set www-ssl certificate=$DOMAIN.pem_0

echo_date ""
echo_date "Cleanup..."
$routeros /file remove $DOMAIN.pem > /dev/null && echo_date " - $DOMAIN.pem removed!"
$routeros /file remove $DOMAIN.key > /dev/null && echo_date " - $DOMAIN.key removed!"
