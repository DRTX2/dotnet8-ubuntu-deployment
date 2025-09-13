

#!/bin/bash
# ------------------------------------------------------------
# Automated deployment script for .NET 8 API
# - Prepares environment, installs dependencies, configures firewall
# - Deploys and publishes the app as systemd service
# - Requires Ubuntu Server 24.04.3 LTS
# ------------------------------------------------------------
set -e

# Log file
LOG_FILE="/var/log/deploy_script.log"

# Global trap for cleanup in case of error/interruption
cleanup() {
    echo "\n⚠️ [INFO] Script interrupted or failed. Review recommended." | tee -a "$LOG_FILE"
    
    # Stop services that might be running
    local SERVICE_NAME="${PROJECT_NAME,,}-service" 2>/dev/null
    if [ -n "$SERVICE_NAME" ] && sudo systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "🛑 Stopping service $SERVICE_NAME..." | tee -a "$LOG_FILE"
        sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    
    # Stop Docker containers if they are running
    if docker ps --format "table {{.Names}}" | grep -q sqlserver 2>/dev/null; then
        echo "🛑 Stopping SQL Server container..." | tee -a "$LOG_FILE"
        docker stop sqlserver 2>/dev/null || true
    fi
    
    echo "🧹 Cleanup completed." | tee -a "$LOG_FILE"
}
trap cleanup EXIT

# Permission check
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script as root or with sudo." | tee -a "$LOG_FILE"
  exit 1
fi

# Configure system timezone
configureTimezone(){
    echo "🕐 Configuring system timezone..." | tee -a "$LOG_FILE"
    sudo timedatectl set-timezone America/Mexico_City | tee -a "$LOG_FILE"
    echo "✅ Timezone configured successfully" | tee -a "$LOG_FILE"
}

updateRepositories(){
    echo "📦 Updating system repositories..." | tee -a "$LOG_FILE"
    sudo apt update | tee -a "$LOG_FILE"
}

upgradeSystem(){
    echo "⬆️ Upgrading system packages..." | tee -a "$LOG_FILE"
    sudo apt upgrade -y | tee -a "$LOG_FILE"
}

# Check that necessary tools are installed

checkGit(){
    echo "🔍 Checking Git..." | tee -a "$LOG_FILE"
    if git --version &>/dev/null; then
        echo "✅ Git is already installed" | tee -a "$LOG_FILE"
    else
        echo "📦 Installing Git..." | tee -a "$LOG_FILE"
        updateRepositories
        sudo apt install git -y | tee -a "$LOG_FILE"
        echo "✅ Git installed successfully" | tee -a "$LOG_FILE"
    fi
}

checkMake(){
    echo "🔍 Checking if Make is installed..." | tee -a "$LOG_FILE"
    if make --version &>/dev/null; then
        echo "✅ Make is already installed" | tee -a "$LOG_FILE"
    else
        echo "📦 Installing Make..." | tee -a "$LOG_FILE"
        updateRepositories
        sudo apt install make -y | tee -a "$LOG_FILE"
        echo "✅ Make installed successfully" | tee -a "$LOG_FILE"
    fi
}

checkDotNet(){
    echo "🔍 Checking .NET SDK..." | tee -a "$LOG_FILE"
    if dotnet --list-sdks &>/dev/null; then
        echo "✅ .NET SDK is already installed" | tee -a "$LOG_FILE"
    else
        echo "📦 Downloading Microsoft repository for .NET..." | tee -a "$LOG_FILE"
        # Download resource and name it
        wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb | tee -a "$LOG_FILE"
        # Install with dpkg
        sudo dpkg -i packages-microsoft-prod.deb | tee -a "$LOG_FILE"
        # Remove installer
        rm packages-microsoft-prod.deb
        echo "✅ Microsoft repository configured" | tee -a "$LOG_FILE"
    fi
}

checkDotNetRuntime(){
    echo "🔍 Checking .NET Runtime/SDK (compilation and development)..." | tee -a "$LOG_FILE"
    if dotnet --list-runtimes &>/dev/null; then
        echo "✅ .NET Runtime is already installed" | tee -a "$LOG_FILE"
    else
        echo "📦 Installing .NET SDK 8.0..." | tee -a "$LOG_FILE"
        updateRepositories
        sudo apt install dotnet-sdk-8.0 -y | tee -a "$LOG_FILE"
        echo "✅ .NET SDK 8.0 installed successfully" | tee -a "$LOG_FILE"
    fi
}

checkSSHServer(){
    echo "🔍 Checking if SSH is installed and active..." | tee -a "$LOG_FILE"
    if ssh -V &>/dev/null; then
        echo "✅ SSH is already installed and active." | tee -a "$LOG_FILE"
    else
        # Install SSH server if not present
        echo "📦 Installing OpenSSH Server..." | tee -a "$LOG_FILE"
        updateRepositories
        sudo apt install openssh-server -y | tee -a "$LOG_FILE"
        # Enable and start SSH service
        echo "🔧 Enabling and starting SSH service..." | tee -a "$LOG_FILE"
        sudo systemctl enable ssh --now | tee -a "$LOG_FILE"
        # Configure sshd_config file
        local SSHD_CONFIG="/etc/ssh/sshd_config"
        echo "🔧 Configuring SSH to listen on all network interfaces..." | tee -a "$LOG_FILE"
        sudo sed -i '/^ListenAddress/d' "$SSHD_CONFIG"
        echo "ListenAddress 0.0.0.0" | sudo tee -a "$SSHD_CONFIG" | tee -a "$LOG_FILE"
        echo "🔧 Disabling root access by password..." | tee -a "$LOG_FILE"
        sudo sed -i '/^PermitRootLogin/d' "$SSHD_CONFIG"
        echo "PermitRootLogin prohibit-password" | sudo tee -a "$SSHD_CONFIG" | tee -a "$LOG_FILE"
        echo "🔧 Enabling password authentication for users..." | tee -a "$LOG_FILE"
        sudo sed -i '/^PasswordAuthentication/d' "$SSHD_CONFIG"
        echo "PasswordAuthentication yes" | sudo tee -a "$SSHD_CONFIG" | tee -a "$LOG_FILE"
        echo "🔄 Restarting SSH service to apply changes..." | tee -a "$LOG_FILE"
        sudo systemctl restart ssh | tee -a "$LOG_FILE"
        echo "⚠️ Server restart required to fully apply SSH changes." | tee -a "$LOG_FILE"
        exit
    fi
}

checkUFW(){
    echo "🔍 Checking UFW (Firewall)..." | tee -a "$LOG_FILE"
    if which ufw &>/dev/null; then
        echo "✅ UFW is already installed" | tee -a "$LOG_FILE"
    else
        echo "📦 Installing UFW..." | tee -a "$LOG_FILE"
        updateRepositories
        sudo apt install ufw -y | tee -a "$LOG_FILE"
        echo "✅ UFW installed successfully" | tee -a "$LOG_FILE"
    fi
}

checkDocker(){
    echo "🔍 Checking Docker..." | tee -a "$LOG_FILE"
    if docker --version &>/dev/null; then
        echo "✅ Docker is already installed" | tee -a "$LOG_FILE"
    else
        echo "📦 Installing Docker..." | tee -a "$LOG_FILE"
        updateRepositories
        upgradeSystem
        # Install dependencies
        echo "📦 Installing Docker dependencies..." | tee -a "$LOG_FILE"
        sudo apt install ca-certificates curl gnupg lsb-release -y | tee -a "$LOG_FILE"
        # Add Docker GPG key
        echo "🔑 Adding Docker GPG key..." | tee -a "$LOG_FILE"
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg | tee -a "$LOG_FILE"
        # Add Docker repository
        echo "📋 Adding Docker repository..." | tee -a "$LOG_FILE"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        # Install Docker
        echo "📦 Installing Docker Engine..." | tee -a "$LOG_FILE"
        updateRepositories
        sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y | tee -a "$LOG_FILE"
        if docker --version &>/dev/null; then
            echo "✅ Docker installed successfully" | tee -a "$LOG_FILE"
        else
            echo "❌ Error installing Docker" | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
}


initSQLServer(){
        echo "🔍 Checking SQL Server..." | tee -a "$LOG_FILE"
        echo "📥 Downloading SQL Server image..." | tee -a "$LOG_FILE"
        docker pull mcr.microsoft.com/mssql/server:2022-latest | tee -a "$LOG_FILE"
        echo "🚀 Starting SQL Server container..." | tee -a "$LOG_FILE"
        docker compose up -d | tee -a "$LOG_FILE"
        # Active wait until container is healthy
        echo "⏳ Waiting for SQL Server to be ready..." | tee -a "$LOG_FILE"
        until [ "$(docker inspect -f '{{.State.Health.Status}}' sqlserver 2>/dev/null)" == "healthy" ]; do
            echo "⏳ Not ready yet, waiting 5s..." | tee -a "$LOG_FILE"
            sleep 5
        done
        echo "✅ SQL Server is ready to accept connections." | tee -a "$LOG_FILE"
}

# Post-installation verification function
verifyDeployment(){
    echo "🔍 Verifying deployment status..." | tee -a "$LOG_FILE"
    
    local SERVICE_NAME="${PROJECT_NAME,,}-service"
    
    # Verify that the service is running
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ Service $SERVICE_NAME is running" | tee -a "$LOG_FILE"
    else
        echo "❌ Service $SERVICE_NAME is not running" | tee -a "$LOG_FILE"
        sudo systemctl status "$SERVICE_NAME" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Verify that SQL Server is running
    if docker ps --format "table {{.Names}}" | grep -q sqlserver; then
        echo "✅ SQL Server container is running" | tee -a "$LOG_FILE"
    else
        echo "❌ SQL Server container is not running" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Verify that ports are listening
    sleep 5  # Give time for services to start completely
    
    if sudo netstat -tlnp | grep ":$CLIENTS_SERVICE_PORT " &>/dev/null; then
        echo "✅ Port $CLIENTS_SERVICE_PORT is listening" | tee -a "$LOG_FILE"
    else
        echo "⚠️ Port $CLIENTS_SERVICE_PORT is not listening" | tee -a "$LOG_FILE"
    fi
    
    if sudo netstat -tlnp | grep ":$ORDERS_SERVICE_PORT " &>/dev/null; then
        echo "✅ Port $ORDERS_SERVICE_PORT is listening" | tee -a "$LOG_FILE"
    else
        echo "⚠️ Port $ORDERS_SERVICE_PORT is not listening" | tee -a "$LOG_FILE"
    fi
    
    if sudo netstat -tlnp | grep ":$DB_PORT " &>/dev/null; then
        echo "✅ Database port $DB_PORT is listening" | tee -a "$LOG_FILE"
    else
        echo "⚠️ Database port $DB_PORT is not listening" | tee -a "$LOG_FILE"
    fi
    
    echo "📋 Services summary:" | tee -a "$LOG_FILE"
    echo "🔹 API: http://localhost:$CLIENTS_SERVICE_PORT" | tee -a "$LOG_FILE"
    echo "🔹 Orders Service: http://localhost:$ORDERS_SERVICE_PORT" | tee -a "$LOG_FILE"
    echo "🔹 Database: localhost:$DB_PORT" | tee -a "$LOG_FILE"
    echo "🔹 Service logs: sudo journalctl -u $SERVICE_NAME -f" | tee -a "$LOG_FILE"
}

# Configure UFW firewall
setupUFW(){
    echo "🔥 Configuring firewall (UFW)..." | tee -a "$LOG_FILE"
    echo "📁 Exporting .env variables..." | tee -a "$LOG_FILE"

    if [ ! -f .env ]; then
        echo "❌ .env file not found. Aborting." | tee -a "$LOG_FILE"
        exit 1
    fi
    set -a
    source .env
    set +a

    # Validation of critical variables
    for var in CLIENTS_SERVICE_PORT ORDERS_SERVICE_PORT PROJECT_NAME PROJECT_USER_FOR_SERVICE PROJECT_GIT_RESOURCE_URL DB_PASSWORD; do
      if [ -z "${!var}" ]; then
        echo "❌ Error: Variable $var is not defined in .env" | tee -a "$LOG_FILE"
        exit 1
      fi
    done

    echo -e "\n📊 Current UFW status:\n" | tee -a "$LOG_FILE"
    sudo ufw status | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    echo "🔍 Checking port usage..." | tee -a "$LOG_FILE"
    if sudo lsof -i :$CLIENTS_SERVICE_PORT &>/dev/null; then
        echo "❌ Client service port $CLIENTS_SERVICE_PORT is already in use!" | tee -a "$LOG_FILE"
        exit 1
    fi

    if sudo lsof -i :$ORDERS_SERVICE_PORT &>/dev/null; then
        echo "❌ Orders service port $ORDERS_SERVICE_PORT is already in use!" | tee -a "$LOG_FILE"
        exit 1
    fi

    if sudo lsof -i :$DB_PORT &>/dev/null; then
        echo "❌ Database port $DB_PORT is already in use!" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "✅ Ports are free, applying UFW configuration..." | tee -a "$LOG_FILE"
    echo "🔒 Ensuring SSH port is available during modifications" | tee -a "$LOG_FILE"
    sudo ufw allow 22/tcp | tee -a "$LOG_FILE"

    echo "🔥 Enabling firewall..." | tee -a "$LOG_FILE"
    sudo ufw --force enable | tee -a "$LOG_FILE"

    echo "🔓 Allowing service ports..." | tee -a "$LOG_FILE"
    sudo ufw allow ${CLIENTS_SERVICE_PORT}/tcp | tee -a "$LOG_FILE"
    sudo ufw allow ${ORDERS_SERVICE_PORT}/tcp | tee -a "$LOG_FILE"
    sudo ufw allow ${DB_PORT}/tcp | tee -a "$LOG_FILE"

    echo -e "\n📊 Final UFW configuration:\n" | tee -a "$LOG_FILE"
    sudo ufw status numbered | tee -a "$LOG_FILE"
}


configUserAndGrants(){
    echo "🔧 Configuring service user and permissions..." | tee -a "$LOG_FILE"
    # To avoid failure if user already exists
    if id "$PROJECT_USER_FOR_SERVICE" &>/dev/null; then
        echo "ℹ️ User $PROJECT_USER_FOR_SERVICE already exists, skipping creation..." | tee -a "$LOG_FILE"
    else
        echo "👤 Creating system user: $PROJECT_USER_FOR_SERVICE" | tee -a "$LOG_FILE"
        sudo useradd -r -s /bin/false "$PROJECT_USER_FOR_SERVICE" | tee -a "$LOG_FILE"
    fi
    
    local PROJECT_DIR="/var/www/$PROJECT_NAME"
    echo "📁 Creating project directory: $PROJECT_DIR" | tee -a "$LOG_FILE"
    sudo mkdir -p "$PROJECT_DIR" | tee -a "$LOG_FILE"
    echo "🔒 Assigning permissions to user $PROJECT_USER_FOR_SERVICE" | tee -a "$LOG_FILE"
    sudo chown -R "$PROJECT_USER_FOR_SERVICE:$PROJECT_USER_FOR_SERVICE" "$PROJECT_DIR" | tee -a "$LOG_FILE"
    echo "✅ User and permissions configured successfully" | tee -a "$LOG_FILE"
}

tryExecuteApp() {
    local PROJECT_DIR="/var/www/$PROJECT_NAME"

    echo "🏗️ Preparing project directory..." | tee -a "$LOG_FILE"
    sudo mkdir -p "$PROJECT_DIR"
    sudo chown -R "$PROJECT_USER_FOR_SERVICE:$PROJECT_USER_FOR_SERVICE" "$PROJECT_DIR"
    cd "$PROJECT_DIR" || { echo "❌ Error: Could not access directory $PROJECT_DIR" | tee -a "$LOG_FILE"; exit 1; }

    echo "📥 Cloning project from $PROJECT_GIT_RESOURCE_URL..." | tee -a "$LOG_FILE"
    # Make sure directory is empty before cloning
    if [ "$(ls -A "$PROJECT_DIR")" ]; then
        echo "🧹 Directory $PROJECT_DIR is not empty. Cleaning..." | tee -a "$LOG_FILE"
        rm -rf "$PROJECT_DIR"/* | tee -a "$LOG_FILE"
    fi
    
    if ! git clone "$PROJECT_GIT_RESOURCE_URL" . 2>&1 | tee -a "$LOG_FILE"; then
        echo "❌ Error cloning repository" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "🔧 Verifying that dotnet ef is available..." | tee -a "$LOG_FILE"
    if ! dotnet tool list -g | grep -q dotnet-ef; then
        echo "📦 Installing Entity Framework Tools..." | tee -a "$LOG_FILE"
        dotnet tool install --global dotnet-ef | tee -a "$LOG_FILE"
    fi

    echo "🗃️ Running database migrations..." | tee -a "$LOG_FILE"
    if ! dotnet ef database update 2>&1 | tee -a "$LOG_FILE"; then
        echo "❌ Error running database migrations" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "🔨 Compiling and publishing project..." | tee -a "$LOG_FILE"
    if ! dotnet publish -c Release -o ./publish 2>&1 | tee -a "$LOG_FILE"; then
        echo "❌ Error compiling project" | tee -a "$LOG_FILE"
        exit 1
    fi

    cd "$PROJECT_DIR/publish" || { echo "❌ Error: Could not access publish directory" | tee -a "$LOG_FILE"; exit 1; }
    echo "✅ Application compiled and ready for deployment" | tee -a "$LOG_FILE"

    # Clean up temporary files if necessary
    # Example: rm -f /tmp/temp_file
}

createSystemdService(){
    echo "⚙️ Creating systemd service..." | tee -a "$LOG_FILE"
    local SERVICE_NAME="${PROJECT_NAME,,}-service" # lowercase
    local SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
    local PROJECT_DIR="/var/www/$PROJECT_NAME/publish"
    local DLL_PATH="$PROJECT_DIR/$PROJECT_NAME.dll"

    # Verify that DLL file exists
    if [ ! -f "$DLL_PATH" ]; then
        echo "❌ Error: File $DLL_PATH not found" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "📝 Creating service file: $SERVICE_FILE" | tee -a "$LOG_FILE"
    sudo bash -c "cat > $SERVICE_FILE <<EOF
[Unit]
Description=Service for $PROJECT_NAME API on Ubuntu
After=network.target

[Service]
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/dotnet $DLL_PATH
Restart=always
RestartSec=10
SyslogIdentifier=$SERVICE_NAME
User=$PROJECT_USER_FOR_SERVICE
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOF" | tee -a "$LOG_FILE"

    echo "🔄 Reloading systemd configuration..." | tee -a "$LOG_FILE"
    sudo systemctl daemon-reload | tee -a "$LOG_FILE"
    echo "✅ Enabling service $SERVICE_NAME..." | tee -a "$LOG_FILE"
    sudo systemctl enable $SERVICE_NAME | tee -a "$LOG_FILE"
    echo "🚀 Starting service $SERVICE_NAME..." | tee -a "$LOG_FILE"
    sudo systemctl start $SERVICE_NAME | tee -a "$LOG_FILE"
    
    # Verify that service is running
    sleep 3
    if sudo systemctl is-active --quiet $SERVICE_NAME; then
        echo "✅ Service $SERVICE_NAME started successfully" | tee -a "$LOG_FILE"
    else
        echo "❌ Error: Service $SERVICE_NAME failed to start" | tee -a "$LOG_FILE"
        sudo systemctl status $SERVICE_NAME | tee -a "$LOG_FILE"
        exit 1
    fi
}

executeScript(){
    echo "🚀 Starting deployment script for Ubuntu Server 24.04.3 LTS" | tee -a "$LOG_FILE"
    echo "📅 Execution date: $(date)" | tee -a "$LOG_FILE"
    
    configureTimezone
    checkGit
    checkMake
    checkDotNet
    checkDotNetRuntime
    checkSSHServer
    checkUFW
    checkDocker
    initSQLServer
    setupUFW
    configUserAndGrants
    tryExecuteApp
    createSystemdService
    verifyDeployment
    
    echo "🎉 Deployment completed successfully!" | tee -a "$LOG_FILE"
    echo "📊 Logs available at: $LOG_FILE" | tee -a "$LOG_FILE"
}

executeScript