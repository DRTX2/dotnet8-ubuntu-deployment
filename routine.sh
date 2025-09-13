

#!/bin/bash
# ------------------------------------------------------------
# Script de despliegue automatizado para API .NET 8
# - Prepara entorno, instala dependencias, configura firewall
# - Despliega y publica la app como servicio systemd
# - Requiere Ubuntu Server 24.04.3 LTS
# ------------------------------------------------------------
set -e

# Archivo de log
LOG_FILE="/var/log/deploy_script.log"

# Trap global para limpieza en caso de error/interrupción
cleanup() {
        echo "\n[INFO] Script interrumpido o fallido. Revisión recomendada." | tee -a "$LOG_FILE"
        # Aquí puedes agregar limpieza de recursos temporales si es necesario
}
trap cleanup EXIT

# Comprobación de permisos
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta este script como root o con sudo." | tee -a "$LOG_FILE"
    exit 1
fi

updateRepositories(){
    sudo apt update
}

upgradeSystem(){
    sudo apt upgrade -y
}

# comprobar herramientas necesarias esten instaladas

checkGit(){
    echo "Comprobando git"
    if git --version &>/dev/null; then
        echo "done"
    else
        updateRepositories
        sudo apt install git -y
    fi
}

checkMake(){
    echo "Checking if make is installed on server"
    if make --version &>/dev/null; then
        echo "done"
    else
        echo "installing make"
        updateRepositories
        sudo apt install make -y
    fi
    echo "done"
}
checkDotNet(){
    echo "Comprobando .net"
    if dotnet --list-sdks &>/dev/null; then
        echo "done"
    else
        # descargar recurso y nombrarlo
        wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
        # instalar con dpkg
        sudo dpkg -i packages-microsoft-prod.deb
        # remover instalador
        rm packages-microsoft-prod.deb
    fi
}


checkDotNetRuntime(){
    echo "Comprobando .net sdk(compilacion y desarrollo)"
    if dotnet --list-runtimes &>/dev/null; then
        echo "done"
    else
        updateRepositories
        sudo apt install dotnet-sdk-8.0 -y
    fi
}

checkSSHServer(){
    echo "Comprobando si SSH está instalado y activo"
    if ssh -V &>/dev/null; then
        echo "SSH ya está instalado y activo."
    else
        # Instala el servidor SSH si no está presente
        echo "Instalando OpenSSH Server..."
        updateRepositories
        sudo apt install openssh-server -y
        # Habilita y arranca el servicio SSH
        echo "Habilitando y arrancando el servicio SSH..."
        sudo systemctl enable ssh --now
        # Configura el archivo sshd_config
        SSHD_CONFIG="/etc/ssh/sshd_config"
        echo "Configurando SSH para escuchar en todas las interfaces de red..."
        sudo sed -i '/^ListenAddress/d' "$SSHD_CONFIG"
        echo "ListenAddress 0.0.0.0" | sudo tee -a "$SSHD_CONFIG"
        echo "Deshabilitando el acceso root por contraseña..."
        sudo sed -i '/^PermitRootLogin/d' "$SSHD_CONFIG"
        echo "PermitRootLogin prohibit-password" | sudo tee -a "$SSHD_CONFIG"
        echo "Habilitando autenticación por contraseña para usuarios..."
        sudo sed -i '/^PasswordAuthentication/d' "$SSHD_CONFIG"
        echo "PasswordAuthentication yes" | sudo tee -a "$SSHD_CONFIG"
        echo "Reiniciando el servicio SSH para aplicar los cambios..."
        sudo systemctl restart ssh
        echo "# Es necesario reiniciar el servidor para aplicar completamente los cambios de SSH."
        exit
    fi
}

checkUFW(){
    echo "Comprobando ufw"
    if which ufw &>/dev/null; then
        echo "done"
    else
        echo "Instalando ufw"
        updateRepositories
        sudo apt install ufw -y
    fi
}

checkDocker(){
    echo "Comprobando docker"
    if docker --version &>/dev/null; then
        echo "done"
    else
        updateRepositories
        upgradeSystem
        # instalar dependencias
        sudo apt install ca-certificates curl gnupg lsb-release -y
        # agregar clave gpg de docker
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        # agregar repo de docker
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        # instalar docker
        updateRepositories
        sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
        if docker --version &>/dev/null; then
            echo "Docker is now installed succesfully"
        else
            echo "Something went wrong installing docker"
        fi
    fi
}


initSQLServer(){
        echo "Comprobando sqlserver" | tee -a "$LOG_FILE"
        echo "Descargando imagen de SQL Server..." | tee -a "$LOG_FILE"
        docker pull mcr.microsoft.com/mssql/server:2022-latest | tee -a "$LOG_FILE"
        echo "Levantando contenedor SQL Server..." | tee -a "$LOG_FILE"
        docker compose up -d | tee -a "$LOG_FILE"
        # Espera activa hasta que el contenedor esté healthy
        echo "Esperando a que SQL Server esté listo..." | tee -a "$LOG_FILE"
        until [ "$(docker inspect -f '{{.State.Health.Status}}' sqlserver 2>/dev/null)" == "healthy" ]; do
            echo "Aún no está listo, esperando 5s..." | tee -a "$LOG_FILE"
            sleep 5
        done
        echo "SQL Server está listo para aceptar conexiones." | tee -a "$LOG_FILE"
}

# configurar ufw
setupUFW(){
    echo "Configuring firewall (ufw)" | tee -a "$LOG_FILE"
    echo "Exporting .env variables..." | tee -a "$LOG_FILE"

    if [ ! -f .env ]; then
        echo "Archivo .env no encontrado. Abortando." | tee -a "$LOG_FILE"
        exit 1
    fi
    set -a
    source .env
    set +a

    # Validación de variables críticas
    for var in CLIENTS_SERVICE_PORT ORDERS_SERVICE_PORT PROJECT_NAME PROJECT_USER_FOR_SERVICE PROJECT_GIT_RESOURCE_URL; do
      if [ -z "${!var}" ]; then
        echo "Error: La variable $var no está definida en .env" | tee -a "$LOG_FILE"
        exit 1
      fi
    done

    echo -e "\nSHOW CURRENT UFW STATUS\n" | tee -a "$LOG_FILE"
    sudo ufw status | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    echo "Checking port usage..." | tee -a "$LOG_FILE"
    if sudo lsof -i :$CLIENTS_SERVICE_PORT &>/dev/null; then
        echo "❌ Client service port $CLIENTS_SERVICE_PORT is already in use!" | tee -a "$LOG_FILE"
        exit 1
    fi

    if sudo lsof -i :$ORDERS_SERVICE_PORT &>/dev/null; then
        echo "❌ Orders service port $ORDERS_SERVICE_PORT is already in use!" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "✅ Ports are free, applying UFW configuration..." | tee -a "$LOG_FILE"
    echo "Ensuring SSH port is available during modifications" | tee -a "$LOG_FILE"
    sudo ufw allow 22/tcp | tee -a "$LOG_FILE"

    sudo ufw enable | tee -a "$LOG_FILE"

    sudo ufw allow ${CLIENTS_SERVICE_PORT}/tcp | tee -a "$LOG_FILE"
    sudo ufw allow ${ORDERS_SERVICE_PORT}/tcp | tee -a "$LOG_FILE"

    echo -e "\n\nShow current ufw configs\n\n" | tee -a "$LOG_FILE"
    sudo ufw status | tee -a "$LOG_FILE"
}


configUserAndGrants(){
    # para que no falle luego de un error por si ya estaba creado
    sudo useradd -r -s /bin/false "$PROJECT_USER_FOR_SERVICE" || true
    sudo mkdir -p "/var/www/$PROJECT_NAME"
    sudo chown -R "$PROJECT_USER_FOR_SERVICE:$PROJECT_USER_FOR_SERVICE" "/var/www/$PROJECT_NAME"
}

tryExecuteApp() {
    PROJECT_DIR="/var/www/$PROJECT_NAME"

    sudo mkdir -p "$PROJECT_DIR"
    sudo chown -R "$PROJECT_USER_FOR_SERVICE:$PROJECT_USER_FOR_SERVICE" "$PROJECT_DIR"
    cd "$PROJECT_DIR" || exit

    echo "Clonando proyecto desde $PROJECT_GIT_RESOURCE_URL..." | tee -a "$LOG_FILE"
    # Asegurarse de que el directorio esté vacío antes de clonar
    if [ "$(ls -A "$PROJECT_DIR")" ]; then
        echo "El directorio $PROJECT_DIR no está vacío. Limpiando..." | tee -a "$LOG_FILE"
        rm -rf "$PROJECT_DIR"/*
    fi
    git clone "$PROJECT_GIT_RESOURCE_URL" . | tee -a "$LOG_FILE"

    echo "Ejecutando migraciones de base de datos..." | tee -a "$LOG_FILE"
    dotnet ef database update | tee -a "$LOG_FILE"

    echo -e "Compilando y publicando el proyecto...\n" | tee -a "$LOG_FILE"
    dotnet publish -c Release -o ./publish | tee -a "$LOG_FILE"

    cd "$PROJECT_DIR/publish" || exit

    # Limpieza de archivos temporales si es necesario
    # Ejemplo: rm -f /tmp/archivo_temp
}

createSystemdService(){
    SERVICE_NAME="${PROJECT_NAME,,}-service" # lowercase
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
    PROJECT_DIR="/var/www/$PROJECT_NAME/publish"
    DLL_PATH="$PROJECT_DIR/$PROJECT_NAME.dll"

    sudo bash -c "cat > $SERVICE_FILE <<EOF
[Unit]
Description=Servicio de la API $PROJECT_NAME en Ubuntu
After=network.target

[Service]
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/dotnet $DLL_PATH
Restart=always
RestartSec=10
SyslogIdentifier=$SERVICE_NAME
User=$PROJECT_USER_FOR_SERVICE

[Install]
WantedBy=multi-user.target
EOF"

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME
    echo "✅ Service $SERVICE_NAME started"
}


executeScript(){
    echo "correra en ubuntu server 24.04.3 LTS, principalmente lo defino porque no hay apt en alma linux"
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
}

executeScript