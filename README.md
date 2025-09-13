# 🚀 .NET 8 API Automated Deployment Script

An automated deployment script for .NET 8 APIs on Ubuntu Server 24.04.3 LTS. This script handles the complete setup process from system preparation to service deployment.

## 📋 Overview

This deployment script automates the entire process of setting up a production-ready .NET 8 API environment, including:

- ✅ System dependencies installation
- 🔒 Security configuration (SSH, UFW firewall)
- 🐳 Docker and SQL Server setup
- 🏗️ Application compilation and deployment
- ⚙️ Systemd service creation
- 🔍 Post-deployment verification

## 🎯 Features

### 🛠️ **System Setup**
- Automatic installation of Git, Make, .NET 8 SDK
- SSH server configuration with security best practices
- UFW firewall setup with custom port rules
- Docker Engine installation and configuration

### 🔒 **Security**
- SSH hardening (disable root password login, enable key-based auth)
- Firewall configuration for specific service ports
- Dedicated system user for service execution
- Proper file permissions and ownership

### 🐳 **Database Management**
- SQL Server 2022 containerization
- Health check validation
- Automatic port configuration
- Volume persistence

### 📦 **Application Deployment**
- Git repository cloning
- Entity Framework migrations
- Release compilation and publishing
- Systemd service creation and management

### 📊 **Monitoring & Logging**
- Comprehensive logging to `/var/log/deploy_script.log`
- Real-time progress indicators with emojis
- Post-deployment verification
- Service status monitoring

## 📁 Project Structure

```
.
├── routine.sh          # Main deployment script
├── docker-compose.yml  # SQL Server container configuration
├── .env               # Environment variables
├── Makefile           # Docker management shortcuts
└── README.md          # This file
```

## ⚙️ Configuration

### Environment Variables (`.env`)

Create a `.env` file with the following variables:

```bash
# Database Configuration
DB_CONNECTION=Server=localhost,1433;Database=YourDB;User Id=sa;Password=YourPassword;Encrypt=True;TrustServerCertificate=True;
DB_SERVERNAME=localhost
DB_PORT=1433
DB_PASSWORD=YourStrongPassword123!

# Service Ports
CLIENTS_SERVICE_PORT=5091
ORDERS_SERVICE_PORT=5092

# Project Configuration
PROJECT_NAME=YourAppName
PROJECT_USER_FOR_SERVICE=yourappuser
PROJECT_GIT_RESOURCE_URL=https://github.com/username/your-repo.git
```

### Docker Compose Configuration

The `docker-compose.yml` file configures SQL Server 2022:

```yaml
services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: sqlserver
    environment:
      ACCEPT_EULA: "Y"
      SA_PASSWORD: "${DB_PASSWORD}"
    ports:
      - "${DB_PORT}:1433"
    volumes:
      - sqlserver-data:/var/opt/mssql
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/opt/mssql-tools/bin/sqlcmd", "-S", "localhost", "-U", "sa", "-P", "${DB_PASSWORD}", "-Q", "SELECT 1"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  sqlserver-data:
```

## 🚀 Usage

### Prerequisites

- Ubuntu Server 24.04.3 LTS
- Root or sudo access
- Internet connection for package downloads

### Quick Start

1. **Clone or download the deployment files:**
   ```bash
   git clone <your-deployment-repo>
   cd routines
   ```

2. **Configure environment variables:**
   ```bash
   cp .env.example .env
   nano .env  # Edit with your configuration
   ```

3. **Make the script executable:**
   ```bash
   chmod +x routine.sh
   ```

4. **Run the deployment:**
   ```bash
   sudo ./routine.sh
   ```

### Alternative: Using Make

You can also use the provided Makefile for Docker operations:

```bash
# Start services
make up

# Stop services
make down

# Restart services
make restart

# View logs
make logs
```

## 📝 What the Script Does

### 1. **System Preparation**
- Updates package repositories
- Configures system timezone
- Installs essential tools (Git, Make, .NET 8, Docker)

### 2. **Security Configuration**
- Configures SSH server with security best practices
- Sets up UFW firewall rules
- Creates dedicated service user

### 3. **Database Setup**
- Pulls SQL Server 2022 Docker image
- Starts containerized database
- Waits for health check confirmation

### 4. **Application Deployment**
- Clones your .NET application from Git
- Installs Entity Framework tools
- Runs database migrations
- Compiles and publishes the application

### 5. **Service Management**
- Creates systemd service file
- Enables and starts the service
- Configures automatic restart on failure

### 6. **Verification**
- Checks service status
- Verifies port availability
- Provides service summary and useful commands

## 📊 Logging

All operations are logged to `/var/log/deploy_script.log` with timestamps and progress indicators:

```bash
# View deployment logs
sudo tail -f /var/log/deploy_script.log

# View service logs
sudo journalctl -u yourappname-service -f
```

## 🔧 Troubleshooting

### Common Issues

1. **Permission Denied:**
   ```bash
   sudo chmod +x routine.sh
   sudo ./routine.sh
   ```

2. **Port Already in Use:**
   - Check `.env` file for port conflicts
   - Stop conflicting services: `sudo systemctl stop <service-name>`

3. **Docker Issues:**
   ```bash
   # Check Docker status
   sudo systemctl status docker
   
   # Restart Docker if needed
   sudo systemctl restart docker
   ```

4. **Service Not Starting:**
   ```bash
   # Check service status
   sudo systemctl status yourappname-service
   
   # View detailed logs
   sudo journalctl -u yourappname-service -n 50
   ```

### Log Locations

- **Deployment logs:** `/var/log/deploy_script.log`
- **Service logs:** `sudo journalctl -u yourappname-service`
- **Docker logs:** `docker logs sqlserver`

## 🛡️ Security Considerations

- The script disables SSH root login with password
- UFW firewall is configured to allow only necessary ports
- Database runs in an isolated Docker container
- Application runs under a dedicated system user
- All sensitive data should be stored in `.env` file (not committed to Git)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built for Ubuntu Server 24.04.3 LTS
- Supports .NET 8 applications
- Uses SQL Server 2022 in Docker containers
- Follows systemd service best practices

---

**Made with ❤️ for automated .NET deployments**