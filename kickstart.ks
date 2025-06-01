# Kickstart File for Fedora 41 Unattended Installation with Docker App from .tar
# Używa moby-engine z repozytoriów Fedory

#version=DEVEL

# System language
lang pl_PL.UTF-8
# Keyboard layouts
keyboard --vckeymap=pl --xlayouts='pl'

# Installation source for Fedora 41
url --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=fedora-41&arch=x86_64
repo --name=updates --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f41&arch=x86_64

# Network information
# dhcp on boot, and set a hostname
network --bootproto=dhcp --device=link --activate --onboot=on
network --hostname=fedora-mdoapp-server # !!! Możesz zmienić hostname !!!

# Root password (encrypted, replace with your own "openssl passwd -6")
# !!! Poniższe hasło to "fedora" - ZMIEŃ JE !!!
rootpw --iscrypted $6$randomsalt$K1bHw7kjm.mH6A0NlJgS0.PsgS8K7bEZcPjvLDeNoLOURzf0A3NhNn2O299ZqgoiNCgRj.faldECkCmvBMjZA0
# User account
# !!! Zmień hasło użytkownika "kaletka" !!!
user --name=kaletka --groups=wheel --password=root --plaintext --gecos="Kaletka User"

# System timezone
timezone Europe/Warsaw --utc

# Partitioning
ignoredisk --only-use=sda # Assuming sda is your target disk
clearpart --all --initlabel # Clear all partitions and initialize label
autopart --type=lvm # Automatic LVM partitioning

# Packages to install
%packages
@^server-product-environment # Lub @^minimal-environment jeśli wolisz mniej
moby-engine   # Zamiast docker-ce, pociąga potrzebne zależności jak containerd
wget          # Nadal potrzebne do pobrania pliku .tar
# docker-compose # Jeśli potrzebujesz Docker Compose, dodaj ten pakiet (z repo Fedory)
%end

# Post-installation script
%post --log=/root/ks-post.log --erroronfail
echo ">>> Starting %post script..."

# --- Docker Setup (using moby-engine from Fedora repos) ---
# Nie ma potrzeby dodawania repozytorium Docker CE ani ponownej instalacji,
# ponieważ moby-engine jest instalowany z repozytoriów Fedory w sekcji %packages.

echo ">>> Enabling Docker service (moby-engine) to start on boot..."
# Nazwa usługi dla moby-engine w Fedorze to zazwyczaj 'docker.service'
systemctl enable docker.service

# --- Application Deployment from .tar ---
DOCKER_TAR_FILE="mdoapp-deploy0image-30.tar"
# !!! ZASTĄP PONIŻSZY ADRES IP I PORT SWOIMI RZECZYWISTYMI WARTOŚCIAMI !!!
TAR_DOWNLOAD_URL="http://192.168.1.10:8000/${DOCKER_TAR_FILE}" # <--- TWÓJ ADRES IP I PORT TUTAJ
LOCAL_TAR_PATH="/opt/docker_images/${DOCKER_TAR_FILE}"
IMAGE_STORAGE_DIR="/opt/docker_images"

# !!! ZASTĄP PONIŻSZE WARTOŚCI SWOIMI RZECZYWISTYMI WARTOŚCIAMI !!!
# Nazwa obrazu i tag, który jest ZAPISANY WEWNĄTRZ PLIKU .TAR
# (to co widziałeś po `docker load` i `docker images` na lokalnej maszynie)
IMAGE_NAME_IN_TAR="mojprojekt/mdoapp:latest" # <--- NAZWA OBRAZU Z PLIKU .TAR TUTAJ
# Nazwa dla uruchamianego kontenera
CONTAINER_NAME="mdoapp-kontener" # <--- NAZWA TWOJEGO KONTENERA
# Mapowanie portów: PORT_HOSTA:PORT_W_KONTENERZE
HOST_PORT="8080" # <--- PORT NA HOŚCIE (VM), przez który będzie dostęp
CONTAINER_PORT="3000" # <--- PORT WEWNĄTRZ KONTENERA, na którym nasłuchuje aplikacja

echo ">>> Creating directory for Docker image storage: ${IMAGE_STORAGE_DIR}"
mkdir -p "${IMAGE_STORAGE_DIR}"

echo ">>> Downloading Docker image .tar file from ${TAR_DOWNLOAD_URL} to ${LOCAL_TAR_PATH}..."
wget -q "${TAR_DOWNLOAD_URL}" -O "${LOCAL_TAR_PATH}"

if [ ! -f "${LOCAL_TAR_PATH}" ]; then
    echo ">>> CRITICAL ERROR: Failed to download ${DOCKER_TAR_FILE} from ${TAR_DOWNLOAD_URL}!"
    echo ">>> Please check the URL, your local HTTP server, and network connectivity of the VM."
    exit 1
fi
echo ">>> Docker image .tar file downloaded successfully."
chmod 644 "${LOCAL_TAR_PATH}"

# --- Create systemd service to load image and run container ---
# This service will run after the system fully boots and Docker service is active.
echo ">>> Creating systemd service: /etc/systemd/system/mdoapp-container.service"
cat << EOF > /etc/systemd/system/mdoapp-container.service
[Unit]
Description=MDOApp Application Container (loaded from .tar)
Requires=docker.service
After=docker.service network-online.target # Wait for network too

[Service]
Type=oneshot
RemainAfterExit=yes

# Load the Docker image from the .tar file
# Output of docker load will go to a log file for debugging
ExecStartPre=/bin/sh -c '/usr/bin/docker load -i ${LOCAL_TAR_PATH} > /var/log/mdoapp_docker_load.log 2>&1'

# Stop and remove any existing container with the same name (ensures clean start)
ExecStartPre=-/usr/bin/docker stop ${CONTAINER_NAME}
ExecStartPre=-/usr/bin/docker rm ${CONTAINER_NAME}

# Run the new container
# The -d flag runs the container in detached mode
ExecStart=/usr/bin/docker run -d --name ${CONTAINER_NAME} -p ${HOST_PORT}:${CONTAINER_PORT} ${IMAGE_NAME_IN_TAR}

[Install]
WantedBy=multi-user.target
EOF

echo ">>> Reloading systemd daemons..."
systemctl daemon-reload

echo ">>> Enabling mdoapp-container.service to start on boot..."
systemctl enable mdoapp-container.service

# Attempt to start Docker service here in %post. It might not be fully functional
# until after the first reboot, but the systemd service above will handle the container.
echo ">>> Attempting to start Docker service (moby-engine) in %post (best effort)..."
systemctl start docker.service &
# Give it a moment (optional, as the systemd service is the primary mechanism)
sleep 5

echo ">>> %post script finished."
%end

# Reboot after installation
reboot
