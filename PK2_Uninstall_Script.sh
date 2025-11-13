#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- DETECCIÓN DEL USUARIO REAL ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Por favor, ejecuta este script con sudo: sudo ./uninstall.sh${NC}"
  exit 1
fi

REAL_USER=$SUDO_USER
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}      Desinstalador de QPickit y pk2cmd       ${NC}"
echo -e "${BLUE}==============================================${NC}"
echo -e "${RED}⚠️  Advertencia: Esto eliminará QPickit y sus configuraciones.${NC}"
read -p "¿Estás seguro? (s/n): " confirm
if [[ $confirm != "s" && $confirm != "S" ]]; then
    echo "Cancelado."
    exit 0
fi

# 1. Eliminar binarios
echo -e "${GREEN}[1/5] Eliminando ejecutables...${NC}"
rm -f /usr/local/bin/pk2cmd
rm -f /usr/local/bin/QPickit
rm -f /usr/local/bin/PK2DeviceFile.dat  # El enlace simbólico

# 2. Eliminar datos del sistema
echo -e "${GREEN}[2/5] Eliminando datos del sistema...${NC}"
rm -rf /usr/share/pk2

# 3. Eliminar archivos del usuario (Iconos y Configs)
echo -e "${GREEN}[3/5] Limpiando archivos del usuario ($REAL_USER)...${NC}"
rm -rf "$REAL_HOME/.local/share/QPickit"
rm -f "$REAL_HOME/.local/share/applications/qpickit.desktop"

# 4. Limpiar PATH en .bashrc
# Usamos sed para borrar la línea que contiene "/usr/share/pk2"
echo -e "${GREEN}[4/5] Limpiando .bashrc...${NC}"
if grep -q "/usr/share/pk2" "$REAL_HOME/.bashrc"; then
    # Crea backup por seguridad antes de tocar .bashrc
    cp "$REAL_HOME/.bashrc" "$REAL_HOME/.bashrc.bak_qpickit"
    # Borra la línea
    sed -i '/\/usr\/share\/pk2/d' "$REAL_HOME/.bashrc"
    echo "Línea eliminada de .bashrc (Backup creado: .bashrc.bak_qpickit)"
fi

# 5. Eliminar reglas UDEV
echo -e "${GREEN}[5/5] Eliminando reglas USB...${NC}"
# Borramos la versión nueva y la vieja por si acaso
rm -f /etc/udev/rules.d/99-microchip.rules
rm -f /etc/udev/rules.d/99-pickit2.rules

# Actualizar base de datos de escritorio
sudo -u "$REAL_USER" update-desktop-database "$REAL_HOME/.local/share/applications" > /dev/null 2>&1

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}      ¡Desinstalación Completa!      ${NC}"
echo -e "${BLUE}==============================================${NC}"
