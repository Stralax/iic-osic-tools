@echo off

:: ========================================================================
:: start_iic.bat - simplified script to start, stop and remove the
::          iic-osic-tools container (updates the image on start)
::
:: This script is modeled after the original start_vnc.bat script from the
:: IIC-OSIC-TOOLS project (Harald Pretl and Georg Zachl, Johannes Kepler
:: University, Institute for Integrated Circuits), which is published under
:: the Apache License 2.0:
::   https://github.com/iic-jku/IIC-OSIC-TOOLS  (file: start_vnc.bat)
::
:: This script has been modified and simplified, and is not affiliated with
:: the original authors.
:: License: Apache License 2.0, http://www.apache.org/licenses/LICENSE-2.0
:: ========================================================================

:: Example of overriding a setting (cmd):
::   set WEB_PORT=8080 && start_iic.bat
:: Dry run (prints the commands instead of executing them):
::   set DRY_RUN=1 && start_iic.bat

:: curl -fsSL https://raw.githubusercontent.com/Stralax/iic-osic-tools/main/start_iic.bat -o start_iic.bat
:: curl -fsSL https://tinyurl.com/iic-start-bat -o start_iic.bat

SETLOCAL

:: ----------------------- SETTINGS (default values) -----------------------
IF NOT DEFINED IMAGE set "IMAGE=lrme/iic-osic-tools:latest"
IF NOT DEFINED NAME set "NAME=iic-osic-tools_xvnc"
IF NOT DEFINED DESIGNS set "DESIGNS=%USERPROFILE%\eda\designs"
IF NOT DEFINED WEB_PORT set "WEB_PORT=80"
IF NOT DEFINED VNC_PORT set "VNC_PORT=5901"
IF NOT DEFINED VNC_PW set "VNC_PW=abc123"
IF NOT DEFINED XKB_KEYBOARD_LAYOUT set "XKB_KEYBOARD_LAYOUT=si"
set "KBD_LAYOUT=%XKB_KEYBOARD_LAYOUT%"
:: DRY_RUN: any value = dry run
:: -------------------------------------------------------------------------

:: Windows has no uid/gid, use the image defaults
set "CUSER=1000:1000"

echo [INFO] Image set to %IMAGE%.
echo [INFO] Design directory set to %DESIGNS%.

:: Dry run: commands are printed (marked with $) but not executed.
:: OUT is where command output goes: hidden normally, shown in a dry run.
set "ECHO_IF_DRY_RUN="
set "OUT=nul"
IF DEFINED DRY_RUN (
    echo [INFO] This is a dry run, all commands will be printed to the shell ^(commands printed but not executed are marked with $^)!
    set "ECHO_IF_DRY_RUN=echo $"
    set "OUT=CON"
)

:: Docker must be installed and running (start Docker Desktop first)
docker info >nul 2>&1
IF ERRORLEVEL 1 (
    echo [ERROR] Docker is not installed or not running. Start Docker Desktop and try again.
    exit /b 1
)

:: ----------------------------- MAIN LOGIC --------------------------------
call :is_running
IF NOT ERRORLEVEL 1 goto :running
call :exists
IF NOT ERRORLEVEL 1 goto :stopped
goto :missing

:: Container is running: stop, or stop & remove.
:running
echo [WARNING] Container is running!
echo [HINT] It can also be stopped with "docker stop %NAME%" and removed with "docker rm %NAME%" if required.
echo.
choice /c sr /n /m "Press s to stop, and r to stop & remove: "
IF ERRORLEVEL 2 goto :running_remove
%ECHO_IF_DRY_RUN% docker stop "%NAME%" > %OUT%
goto :eof
:running_remove
%ECHO_IF_DRY_RUN% docker stop "%NAME%" > %OUT%
%ECHO_IF_DRY_RUN% docker rm "%NAME%" > %OUT%
goto :eof

:: Container exists but is stopped: start (with update check), or remove.
:stopped
echo [WARNING] Container %NAME% exists.
echo [HINT] It can also be restarted with "docker start %NAME%" or removed with "docker rm %NAME%" if required.
echo.
choice /c sr /n /m "Press s to start, and r to remove: "
IF ERRORLEVEL 2 goto :stopped_remove
call :start_existing
goto :eof
:stopped_remove
%ECHO_IF_DRY_RUN% docker rm "%NAME%" > %OUT%
goto :eof

:: Container does not exist: check for a newer image, then create and start it.
:missing
call :pull_image
call :create
goto :eof

:: ----------------------------- FUNCTIONS ---------------------------------

:: Returns 0 if the container is running, 1 otherwise.
:is_running
set "STATE="
for /f %%v in ('docker container inspect -f "{{.State.Running}}" "%NAME%" 2^>nul') do set "STATE=%%v"
IF "%STATE%"=="true" exit /b 0
exit /b 1

:: Returns 0 if the container exists (running or stopped), 1 otherwise.
:exists
docker container inspect "%NAME%" >nul 2>&1
exit /b %ERRORLEVEL%

:info
echo [INFO] To access the VNC session, open a browser and navigate to http://localhost:%WEB_PORT%/?password=%VNC_PW%
exit /b 0

:: Watch a detached container for N seconds (default 3) and dump its log if it
:: dies, which would otherwise pass unnoticed. Returns 1 if it stopped.
:check_container_alive
set "TIMEOUT=%~1"
IF NOT DEFINED TIMEOUT set "TIMEOUT=3"
IF DEFINED DRY_RUN exit /b 0
echo [INFO] Verifying that the container stays up ^(up to %TIMEOUT%s^) ...
set /a I=0
:alive_loop
set /a I+=1
ping -n 2 127.0.0.1 >nul
set "STATE="
for /f %%v in ('docker container inspect -f "{{.State.Running}}" "%NAME%" 2^>nul') do set "STATE=%%v"
IF NOT "%STATE%"=="true" goto :alive_failed
IF %I% LSS %TIMEOUT% goto :alive_loop
exit /b 0
:alive_failed
echo [ERROR] Container %NAME% stopped %I%s after it was started.
echo [ERROR] Last lines of "docker logs %NAME%":
for /f "delims=" %%l in ('docker logs --tail 20 "%NAME%" 2^>^&1') do echo     %%l
exit /b 1

:: Creates and starts a new container.
:create
IF NOT EXIST "%DESIGNS%" %ECHO_IF_DRY_RUN% mkdir "%DESIGNS%"
echo [INFO] Container does not exist, creating %NAME% ...
%ECHO_IF_DRY_RUN% docker run -d --user %CUSER% --security-opt seccomp=unconfined -p %WEB_PORT%:80 -p %VNC_PORT%:5901 -e VNC_PW=%VNC_PW% -e XKB_KEYBOARD_LAYOUT=%KBD_LAYOUT% -v "%DESIGNS%":/foss/designs:rw --name %NAME% %IMAGE% > %OUT%
IF ERRORLEVEL 1 (
    echo [ERROR] Could not start the container %NAME%!
    echo [HINT] A leftover container can be removed with "docker rm %NAME%".
    exit /b 1
)
:: Do not advertise a URL for a container that already died.
call :check_container_alive 3
IF ERRORLEVEL 1 exit /b 1
call :info
exit /b 0

:: Pulls the newest image (only downloads if a newer one exists).
:: Returns 0 if the pull worked, 1 if it failed (e.g. no internet).
:pull_image
echo [INFO] Checking for a newer version of %IMAGE% ...
%ECHO_IF_DRY_RUN% docker pull -q "%IMAGE%" > %OUT%
IF ERRORLEVEL 1 (
    echo [WARNING] Could not check for updates ^(offline?^), using the local image.
    exit /b 1
)
exit /b 0

:: Starts the existing (stopped) container. If a newer image was pulled, the
:: user is asked for confirmation ("u") before the old container is removed
:: and re-created from the new image. "n" starts the old container.
:start_existing
call :pull_image
IF ERRORLEVEL 1 goto :start_existing_run
IF DEFINED DRY_RUN goto :start_existing_run

set "IMG_ID="
set "CTR_IMG="
for /f "delims=" %%i in ('docker image inspect -f "{{.Id}}" "%IMAGE%" 2^>nul') do set "IMG_ID=%%i"
for /f "delims=" %%i in ('docker inspect -f "{{.Image}}" "%NAME%" 2^>nul') do set "CTR_IMG=%%i"

IF NOT DEFINED IMG_ID goto :start_existing_run
IF NOT DEFINED CTR_IMG goto :start_existing_run
IF "%IMG_ID%"=="%CTR_IMG%" (
    echo [INFO] Image is up to date.
    goto :start_existing_run
)

echo [INFO] A newer image of %IMAGE% is available.
echo [WARNING] Updating removes the old container %NAME% and creates a new one.
echo [WARNING] Files stored outside of %DESIGNS% - mounted to /foss/designs - will be lost!
echo.
choice /c un /n /m "Press u to update (re-create the container), n to start the old one: "
IF ERRORLEVEL 2 (
    echo [INFO] Update skipped, starting the old container.
    goto :start_existing_run
)
echo [INFO] Updating, re-creating the container ...
docker rm "%NAME%" > %OUT%
docker rmi "%CTR_IMG%" >nul 2>&1
call :create
exit /b %ERRORLEVEL%

:start_existing_run
%ECHO_IF_DRY_RUN% docker start "%NAME%"
IF ERRORLEVEL 1 (
    echo [ERROR] Could not start the container %NAME%.
    exit /b 1
)
call :check_container_alive 3
IF ERRORLEVEL 1 exit /b 1
call :info
exit /b 0