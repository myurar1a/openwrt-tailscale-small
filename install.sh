#!/bin/ash

# --- Configuration ---
CRON_SCHEDULE="0 */6 * * *"
CRON_SCRIPT="upd-tailscale.sh"
INSTALL_DIR="$HOME/scripts"
INSTALL_PATH="$INSTALL_DIR/$CRON_SCRIPT"
# ---------------------

set -e
echo "=== OpenWrt Small Tailscale Installer ==="


echo "[1/7] Checking dependencies..."
if ! opkg list-installed | grep -q "curl"; then
    opkg update && opkg install curl
fi
if ! opkg list-installed | grep -q "ca-bundle"; then
    opkg update && opkg install ca-bundle
fi
if ! opkg list-installed | grep -q "kmod-tun"; then
    opkg update && opkg install kmod-tun
fi


echo "[2/7] Detecting architecture..."
ARCH=$(opkg print-architecture | awk 'END {print $2}')
REPO_URL="https://myurar1a.github.io/openwrt-tailscale-small/${ARCH}"

# Checking repository...
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${REPO_URL}/Packages.gz")

if [ "$HTTP_CODE" != "200" ]; then
    echo "Error: Repository not found for architecture '${ARCH}'."
    echo "URL: ${REPO_URL}"
    echo "Please check if your device architecture is supported in the GitHub repository."
    exit 1
fi
echo "Target: $ARCH"


echo "[3/7] Installing Public Key..."
KEY_DIR="/etc/opkg/keys"
if [ ! -d "$KEY_DIR" ]; then
    mkdir -p "$KEY_DIR"
fi

# Download public key
RAW_URL="https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-small/refs/heads/main"
PUBKEY_NAME="myurar1a-repo.pub"
if curl -sL "$RAW_URL/cert/$PUBKEY_NAME" -o "$KEY_DIR/$PUBKEY_NAME"; then
    echo "Public key installed to $KEY_DIR/$PUBKEY_NAME"
else
    echo "Error: Failed to download public key."
    exit 1
fi


echo "[4/7] Configuring repository..."
FEED_CONF="/etc/opkg/customfeeds.conf"
if ! grep -q "custom_tailscale" "$FEED_CONF"; then
    echo "src/gz custom_tailscale ${REPO_URL}" >> "$FEED_CONF"
fi
if ! grep -q "option check_signature 0" "$FEED_CONF"; then
    echo "option check_signature 0" >> "$FEED_CONF"
fi


echo "[5/7] Installing Tailscale..."
if ! opkg update; then
    echo "Error: 'opkg update' failed. Signature verification might have failed."
    echo "Please check if the repository is correctly signed."
    exit 1
fi

INSTALLED=$(opkg list-installed tailscale | awk '{print $3}')
if [ -n "$INSTALLED" ]; then
    echo "Tailscale is already installed ($INSTALLED)."
    printf "Re-install to ensure latest version? [y/N]: "
    read ANSWER
    if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
        opkg remove tailscale
        opkg install tailscale
    fi
else
    opkg install tailscale
fi


echo "[6/7] Installing auto-update script..."

# Create directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

curl -sL "$RAW_URL/install.sh" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo "Script installed to $INSTALL_PATH"


echo "[7/7] Scheduling Cron job..."

if crontab -l 2>/dev/null | grep -q "$INSTALL_PATH"; then
    echo "Cron job already exists."
else
    (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE $INSTALL_PATH") | crontab -
    echo "Cron job added."
    /etc/init.d/cron restart
fi

echo ""
echo "=== Installation Complete! ==="