#!/bin/bash

# Colores para la salida
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- DETECCIÓN DEL USUARIO REAL ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Por favor, ejecuta este script con sudo: sudo ./install.sh${NC}"
  exit 1
fi

# Obtenemos el usuario real que llamó a sudo
REAL_USER=$SUDO_USER
# Obtenemos el home del usuario real
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}    Instalador Automatizado PICkit 2 (Mint 22.2)   ${NC}"
echo -e "${BLUE}    Usuario detectado: ${REAL_USER}                ${NC}"
echo -e "${BLUE}==============================================${NC}"

# 1. Instalar Dependencias
echo -e "${GREEN}[1/6] Instalando dependencias necesarias...${NC}"
apt-get update
apt-get install -y build-essential libusb-1.0-0-dev qtchooser qt5-qmake qtbase5-dev git wget

# 2. Crear directorio de trabajo temporal
TEMP_DIR="$REAL_HOME/temp_pk2_install"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# 3. Descargar y Compilar pk2cmd (Línea de comandos)
echo -e "${GREEN}[2/6] Descargando y compilando pk2cmd...${NC}"
git clone https://github.com/jaka-fi/pk2cmd.git
cd pk2cmd/pk2cmd
make linux

# Instalar binario
cp pk2cmd /usr/local/bin/
# Instalar base de datos de dispositivos
mkdir -p /usr/share/pk2
cp PK2DeviceFile.dat /usr/share/pk2/
chmod 644 /usr/share/pk2/PK2DeviceFile.dat

# Agregar al PATH del usuario (no del root) si no existe
if ! grep -q "/usr/share/pk2" "$REAL_HOME/.bashrc"; then
    echo 'export PATH="$PATH:/usr/share/pk2"' >> "$REAL_HOME/.bashrc"
    echo "PATH actualizado en .bashrc"
fi

# Regresar al temp
cd "$TEMP_DIR"

# 4. Descargar y Compilar QPickit (Interfaz Gráfica)
echo -e "${GREEN}[3/6] Descargando y compilando QPickit...${NC}"
git clone https://github.com/GTRONICK/QPickit.git
cd QPickit

qmake QPickit.pro
make

# Instalar el ejecutable
cp QPickit /usr/local/bin/

# --- INSTALACIÓN DE RECURSOS DEL USUARIO ---
# Creamos la carpeta de recursos en el Home del usuario
USER_SHARE="$REAL_HOME/.local/share/QPickit"
mkdir -p "$USER_SHARE/img"

cp img/* "$USER_SHARE/img/"

# IMPORTANTE: Cambiamos el dueño de esos archivos al usuario real (ahora son de root)
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/QPickit"

# Enlace simbólico para el .dat
ln -sf /usr/share/pk2/PK2DeviceFile.dat /usr/local/bin/PK2DeviceFile.dat

# 5. Configuración de Permisos (Método Seguro con Grupos)
echo -e "${GREEN}[4/6] Configurando grupo y permisos USB (PK2/PK3/PKOB)...${NC}"

# 51. Crear grupo 'microchip' si no existe
if ! getent group microchip > /dev/null; then
  groupadd microchip
fi

# 52. Agregar al usuario real al grupo
usermod -aG microchip "$REAL_USER"

# 53. CREAR LAS REGLAS UDEV (Fundamental para que el grupo funcione)
# Aquí definimos que PK2, PK3 y PKOB pertenezcan al grupo 'microchip'
# VID 04D8 es Microchip. 
# PID 0033 = PICkit 2
# PID 900A = PICkit 3
# PID 00DE = MCP2200 (A veces usado en herramientas)
# La regla genérica cubre variantes de PKOB.

# VERIFICACIÓN Y CREACIÓN DE REGLAS UDEV
RULES_FILE="/etc/udev/rules.d/99-microchip.rules"

# Comprobamos si el archivo existe Y si ya contiene la regla del PICkit 2 (idProduct 0033)
if [ -f "$RULES_FILE" ] && grep -q "idProduct.*0033" "$RULES_FILE"; then
    echo -e "${BLUE}   ℹ️  Las reglas UDEV ya existen en $RULES_FILE.${NC}"
    echo -e "${BLUE}       No se sobrescribió el archivo para respetar tu configuración actual.${NC}"
else
    echo "Escribiendo nuevas reglas en $RULES_FILE..."
    
    # Usamos > para crear/sobrescribir SOLO si no existían las reglas correctas
    cat <<EOF > "$RULES_FILE"
# Reglas UDEV para programadores Microchip (Generado por script de instalación)
# PICkit 2
SUBSYSTEM=="usb", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="0033", GROUP="microchip", MODE="0660"
# PICkit 3
SUBSYSTEM=="usb", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="900a", GROUP="microchip", MODE="0660"
# PICkit 3 Scripting
SUBSYSTEM=="usb", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="9009", GROUP="microchip", MODE="0660"
# PKOB y Debuggers Genéricos (Cuidado: 'xxxx' es un placeholder, ajusta si conoces el ID exacto)
SUBSYSTEM=="usb", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="xxxx", GROUP="microchip", MODE="0660"
EOF

    # Solo recargamos si hubo cambios
    udevadm control --reload-rules && udevadm trigger
    echo "Reglas aplicadas."
fi

echo -e "${RED}IMPORTANTE: Debes CERRAR SESIÓN o reiniciar para que los permisos de grupo se apliquen.${NC}"

# 6. Crear el Icono de Escritorio (.desktop)
echo -e "${GREEN}[5/6] Creando acceso directo en el menú...${NC}"

APP_DIR="$REAL_HOME/.local/share/applications"
mkdir -p "$APP_DIR"

# Creamos el archivo .desktop usando las variables REAL_HOME
cat <<EOF > "$APP_DIR/qpickit.desktop"
[Desktop Entry]
Version=1.0
Name=QPickit 2
Comment=Interfaz Gráfica para pk2cmd
Exec=/usr/local/bin/QPickit
Icon=$REAL_HOME/.local/share/QPickit/img/icon.png
Terminal=false
Type=Application
Categories=Development;Electronics;
EOF

# Ajustamos permisos y dueño del acceso directo
chmod +x "$APP_DIR/qpickit.desktop"
chown "$REAL_USER:$REAL_USER" "$APP_DIR/qpickit.desktop"

# Actualizar base de datos del usuario real
# Usamos 'sudo -u' para ejecutar el update como el usuario normal
sudo -u "$REAL_USER" update-desktop-database "$APP_DIR" > /dev/null 2>&1

# 7. Limpieza
echo -e "${GREEN}[6/6] Limpiando archivos temporales...${NC}"
cd "$REAL_HOME"
rm -rf "$TEMP_DIR"

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   ¡Instalación Completa!   ${NC}"
echo -e "${BLUE}   Busca 'QPickit 2' en tu menú de aplicaciones.${NC}"
echo -e "${BLUE}==============================================${NC}"
