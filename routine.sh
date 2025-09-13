#!/bin/bash

updateRepositories(){
    sudo apt update
}

upgradeSystem(){
    sudo apt upgrade
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
        sudo apt install make
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
    echo "Comprobando ssh"
    if ssh -V &>/dev/null; then
        echo "done"
    else
        updateRepositories
        sudo apt install openssh-server -y
        sudo ssytemctl enable ssh --now
        echo "Configurando ssh..."
        echo "Permitiendo que el servicio SSH escuche todas las interfaces de la red disponibles."
        echo "ListenAddress 0.0.0.0" > /etc/ssh/sshd?config
        echo "Deshabilitando el acceso directo como root mediante contraseña."
        echo "PermitRootLogin prohibit-password" > /etc/ssh/sshd?config
        echo "Habilitando autentificación con contraseña para iniciar sesión desde clientes externos a la red en la que se encuentra"
        echo "PasswordAuthentication yes" > /etc/ssh/sshd?config
        sudo systemctl restart ssh
        echo "Es necesario reiniciar el servidor para aplicar cambios"
        exit;
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
    if(docker --version &>/dev/null) then
        echo "done"
    else
        updateRepositories
        upgradeSystem
        # instalar dependencias
        # ca-certificates es para https, gnupg para verificar firmas, lsb-release es para saber version de la distro
        sudo apt install ca-certificates curl gnupg lsb-release -y
        # agregar clave gpg de docker
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        # agregar repo de docker
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        # instalar docker
        updateRepositories
        sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
        if(docker --version &>/dev/null) then
            echo "Docker is now installed succesfully"
        else
            echo "Something went wrong installing docker"
        fi
        # comprobar con docker hello world
    fi
}


initSQLServer(){
    echo "Comprobando sqlserver"
    echo "done"
    docker pull mcr.microsoft.com/mssql/server:2022-latest
    docker compose  up 
    # creo que mejor lo edito tipo que se activen varias cosas pesadas mejor antes de levantar lo necesario
}

# configurar ufw
setupUFW(){
    echo "Configuring firewall (ufw)"
    echo "Exporting .env variables..."

    # Export variables automáticamente
    set -a
    source .env
    # disable feature
    set +a

    echo -e "\nSHOW CURRENT UFW STATUS\n"
    sudo ufw status
    echo ""

    echo "Checking port usage..."
    if sudo lsof -i :$CLIENTS_SERVICE_PORT &>/dev/null; then
        echo "❌ Client service port $CLIENTS_SERVICE_PORT is already in use!"
        exit 1
    fi

    if sudo lsof -i :$ORDERS_SERVICE_PORT &>/dev/null; then
        echo "❌ Orders service port $ORDERS_SERVICE_PORT is already in use!"
        exit 1
    fi

    echo "✅ Ports are free, applying UFW configuration..."
    echo "Ensuring SSH port is available during modifications"
    sudo ufw allow 22/tcp

    sudo ufw enable

    sudo ufw allow ${CLIENTS_SERVICE_PORT}/tcp
    sudo ufw allow ${ORDERS_SERVICE_PORT}/tcp

    echo -e "\n\nShow current ufw configs\n\n"
    sudo ufw status
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

    echo "Cloning project"
    # Asegurarse de que el directorio esté vacío antes de clonar
    if [ "$(ls -A "$PROJECT_DIR")" ]; then
        echo "El directorio $PROJECT_DIR no está vacío. Limpiando..."
        rm -rf "$PROJECT_DIR"/*
    fi
    git clone "$PROJECT_GIT_RESOURCE_URL" .

    echo "Migrating data"
    dotnet ef database update

    echo -e "Complete\n"
    echo "Compiling project"
    dotnet publish -c Release -o ./publish

    cd "$PROJECT_DIR/publish" || exit

    trap "echo 'App interrumpida por el usuario'; return" SIGINT
    dotnet "$PROJECT_NAME.dll"
    trap - SIGINT
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
    deploy
}

executeScript