#!/bin/bash
# ========================================================================
# start_icc.sh - simplified script to start, stop and remove the
#          iic-osic-tools container (updates the image on start)
#
# This script is modeled after the original start_vnc.sh script from the
# IIC-OSIC-TOOLS project (Harald Pretl and Georg Zachl, Johannes Kepler
# University, Institute for Integrated Circuits), which is published under
# the Apache License 2.0:
#   https://github.com/iic-jku/IIC-OSIC-TOOLS  (file: start_vnc.sh)
#
# This script has been modified and simplified, and is not affiliated with
# the original authors.
# License: Apache License 2.0, http://www.apache.org/licenses/LICENSE-2.0
# ========================================================================

# Download command:
# curl -fsSLO https://raw.githubusercontent.com/Stralax/iic-osic-tools/main/start_icc.sh -o start_icc.sh
# curl -fsSL https://tinyurl.com/icc-start-sh -o start_icc.sh

# ----------------------- SETTINGS (default values) -----------------------
IMAGE="${IMAGE:-stralax/iic-osic-tools:latest}"
NAME="${NAME:-iic-osic-tools_xvnc_uid_$(id -u)}"
DESIGNS="${DESIGNS:-$HOME/eda/designs}"
WEB_PORT="${WEB_PORT:-80}"
VNC_PORT="${VNC_PORT:-5901}"
VNC_PW="${VNC_PW:-abc123}"
KBD_LAYOUT="${XKB_KEYBOARD_LAYOUT:-si}"
DRY_RUN="${DRY_RUN:-}"
# -------------------------------------------------------------------------

echo "[INFO] Image set to ${IMAGE}."
echo "[INFO] Design directory set to ${DESIGNS}."

# Dry run: commands are printed (marked with $) but not executed.
# OUT is where command output goes: hidden normally, shown in a dry run.
OUT=/dev/null
if [ -n "${DRY_RUN}" ]; then
    echo "[INFO] This is a dry run, all commands will be printed to the shell (commands printed but not executed are marked with \$)!"
    ECHO_IF_DRY_RUN="echo \$"
    OUT=/dev/stdout
fi

# On Linux use the current uid/gid, elsewhere use 1000
if [[ "$OSTYPE" == "linux"* ]]; then
    CUSER="$(id -u):$(id -g)"
else
    CUSER="1000:1000"
fi

# Extra parameters for special hosts
EXTRA=""
# Apple Silicon:
if [[ "$OSTYPE" == "darwin"* ]] && [ "$(uname -m)" = "arm64" ]; then
    EXTRA="$EXTRA -e OPENSSL_armcap=0"
fi
# SELinux (Fedora, RHEL, ...)
if [[ "$OSTYPE" == "linux"* ]] && command -v selinuxenabled > /dev/null 2>&1 && selinuxenabled; then
    EXTRA="$EXTRA --security-opt label=disable"
    echo "[INFO] SELinux detected, adding \"--security-opt label=disable\"."
fi

# Read-only checks, these always run (also in a dry run)
is_running() { [ -n "$(docker ps -q -f name="^${NAME}$")" ]; }
exists()     { [ -n "$(docker ps -aq -f name="^${NAME}$")" ]; }

# Watch a detached container for $1 seconds (default 3) and dump its log if it
# dies, which would otherwise pass unnoticed. Returns 1 if it stopped.
check_container_alive() {
    local timeout=${1:-3}
    local i
    if [ -n "${DRY_RUN}" ]; then
        return 0
    fi
    echo "[INFO] Verifying that the container stays up (up to ${timeout}s) ..."
    for ((i=1; i<=timeout; i++)); do
        sleep 1
        if [ "$(docker inspect -f '{{.State.Running}}' "${NAME}" 2>/dev/null)" != "true" ]; then
            echo "[ERROR] Container ${NAME} stopped ${i}s after it was started."
            echo "[ERROR] Last lines of \"docker logs ${NAME}\":"
            docker logs --tail 20 "${NAME}" 2>&1 | sed -e 's/^/    /'
            return 1
        fi
    done
    return 0
}

info() {
    echo "[INFO] To access the VNC session, open a browser and navigate to http://localhost:${WEB_PORT}/?password=${VNC_PW}"
}

create() {
    if [ ! -d "$DESIGNS" ]; then
        ${ECHO_IF_DRY_RUN} mkdir -p "$DESIGNS"
    fi
    echo "[INFO] Container does not exist, creating ${NAME} ..."
    # shellcheck disable=SC2086
    if ! ${ECHO_IF_DRY_RUN} docker run -d \
        --user "$CUSER" \
        --security-opt seccomp=unconfined \
        -p "${WEB_PORT}:80" -p "${VNC_PORT}:5901" \
        -e VNC_PW="$VNC_PW" \
        -e XKB_KEYBOARD_LAYOUT="$KBD_LAYOUT" \
        $EXTRA \
        -v "${DESIGNS}:/foss/designs:rw" \
        --name "$NAME" "$IMAGE" > /dev/null; then
        echo "[ERROR] Could not start the container ${NAME}!"
        echo "[HINT] A leftover container can be removed with \"docker rm ${NAME}\"."
        exit 1
    fi
    # Do not advertise a URL for a container that already died.
    check_container_alive 3 || exit 1
    info
}

# Pulls the newest image (only downloads if a newer one exists).
# Returns 0 if the pull worked, 1 if it failed (e.g. no internet).
pull_image() {
    echo "[INFO] Checking for a newer version of ${IMAGE} ..."
    if ! ${ECHO_IF_DRY_RUN} docker pull -q "$IMAGE" > "$OUT"; then
        echo "[WARNING] Could not check for updates (offline?), using the local image."
        return 1
    fi
    return 0
}
# Starts the existing (stopped) container. If a newer image was pulled, the
# old container is removed and re-created from the new image instead.
start_existing() {
    if pull_image && [ -z "${DRY_RUN}" ]; then
        local img_id ctr_img
        img_id=$(docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null)
        ctr_img=$(docker inspect -f '{{.Image}}' "$NAME" 2>/dev/null)
        if [ -n "$img_id" ] && [ -n "$ctr_img" ] && [ "$img_id" != "$ctr_img" ]; then
            echo "[INFO] Newer image found, re-creating the container ..."
            docker rm "$NAME" > "$OUT"
            create
            return
        fi
        echo "[INFO] Image is up to date."
    fi
    # docker start prints the container name, so its output is not hidden.
    if ! ${ECHO_IF_DRY_RUN} docker start "$NAME"; then
        echo "[ERROR] Could not start the container ${NAME}."
        exit 1
    fi
    check_container_alive 3 || exit 1
    info
}

# Container is running: stop, or stop & remove.
if is_running; then
    echo "[WARNING] Container is running!"
    echo "[HINT] It can also be stopped with \"docker stop ${NAME}\" and removed with \"docker rm ${NAME}\" if required."
    echo
    echo -n "Press \"s\" to stop, and \"r\" to stop & remove: "
    read -r -n 1 k </dev/tty
    echo
    if [[ $k = s ]]; then
        ${ECHO_IF_DRY_RUN} docker stop "$NAME" > "$OUT"
    elif [[ $k = r ]]; then
        ${ECHO_IF_DRY_RUN} docker stop "$NAME" > "$OUT"
        ${ECHO_IF_DRY_RUN} docker rm "$NAME" > "$OUT"
    fi

# Container exists but is stopped: start (with update check), or remove.
elif exists; then
    echo "[WARNING] Container ${NAME} exists."
    echo "[HINT] It can also be restarted with \"docker start ${NAME}\" or removed with \"docker rm ${NAME}\" if required."
    echo
    echo -n "Press \"s\" to start, and \"r\" to remove: "
    read -r -n 1 k </dev/tty
    echo
    if [[ $k = s ]]; then
        start_existing
    elif [[ $k = r ]]; then
        ${ECHO_IF_DRY_RUN} docker rm "$NAME" > "$OUT"
    fi

# Container does not exist: check for a newer image, then create and start it.
else
    pull_image
    create
fi
