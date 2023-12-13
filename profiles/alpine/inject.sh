#!/bin/bash

if [[ "${ENV_NAME}" == "dev" ]]; then
    echo "DEVELOPMENT mode"
    export APP_DEV_MODE=1
else
    #todo:design: include another envs, if necessary
    echo "PRODUCTION mode"
    export APP_DEV_MODE=0
fi

#Filter and assign command line arguments
declare -a FREE_ARGS
for arg in "$@"; do
    if [[ "${arg}" == *'='* ]]; then
        #Test environment variable dev is set
        if [[ "${APP_DEV_MODE}" == '1' ]]; then
            echo "VALOR -> ${arg}"
        fi
        eval "INPUT_ARG_$arg"
    else
        echo "argumento livre( ${arg} )"
        FREE_ARGS+=("$arg")
    fi
done

#Define root directory global variable
if [[ -z "${INPUT_ARG_rootdir}" ]]; then
    APP_ROOT_PATH=$(dirname "$0") #"${PWD}" #Root from project as default
else
    APP_ROOT_PATH="${INPUT_ARG_rootdir}"
fi

#Define APP_ENV_NAME global variable
if [[ -n "${INPUT_ARG_env}" ]]; then
    APP_ENV_NAME="${INPUT_ARG_env}" #Using env forced by from command line
else
    APP_ENV_NAME="$ENV_NAME" #using env var from process calling
fi

#Define APP_LIB_DIR global variable and export all globals from now
APP_LIB_DIR=$( dirname "${APP_ROOT_PATH}/../../lib/" )
APP_DBG_DIR="${APP_ROOT_PATH}/../../lib/debug"
export APP_ROOT_PATH
export APP_DBG_DIR
export APP_LIB_DIR
export APP_ENV_NAME

# shellcheck source=/dev/null
source "${APP_LIB_DIR}/utilsFuncs.sh"
# shellcheck source=/dev/null
source "${APP_LIB_DIR}/cfgFuncs.sh"

#*Observar a ordem dos omissos
#*Cuidado para não ler valores errados
#Coleta dos omissos: target, login, pass, environment pela ordem
declare bypass=0
if [[ -z "${INPUT_ARG_target}" ]]; then
    TARGET=${FREE_ARGS[bypass]}
    ((bypass++))
else
    TARGET="$INPUT_ARG_target"
fi

if [[ -z "${INPUT_ARG_login}" ]]; then
    SSH_USER=${FREE_ARGS[bypass]}
    ((bypass++))
else
    SSH_USER="$INPUT_ARG_login"
fi
if [[ -z "${INPUT_ARG_pw}" ]]; then
    SSH_PASSWORD=${FREE_ARGS[bypass]}
    ((bypass++))
else
    SSH_PASSWORD="$INPUT_ARG_pw"
fi

#Loads vars from .env files
process_env "$APP_ROOT_PATH" "$APP_ENV_NAME"
#Show vars if debug mode
debug_show_vars

#Test if target is a valid IP
if [ -n "$TARGET" ]; then
    #Using complete_target_address to get final value to target
    declare resolvedTarget
    complete_target_address resolvedTarget "$TARGET"
    if [ -n "$resolvedTarget" ]; then
        TARGET="$resolvedTarget"
    else
        echo "Informe final do IP do dispositivo ou seru nome para a injeção!"
        exit
    fi
else
    echo "Informe os dados do alvo para a injeção!"
    exit
fi

#Fixing omitted(last chance)
if [ -z "$SSH_USER" ]; then
    SSH_USER="$APP_DOMAIN_ADM_ACCOUNT"
fi
if [ -z "$SSH_PASSWORD" ]; then
    SSH_PASSWORD="$APP_DOMAIN_ADM_ACCOUNT_PWD"
fi

#read values for SSH_USER and SSH_PASSWORD if not set
if [ -z "$SSH_USER" ]; then
    read -p "Informe o login do usuário: " -r SSH_USER
fi
if [ -z "$SSH_PASSWORD" ]; then
    read -p "Informe a senha do usuário: " -r -s SSH_PASSWORD
    echo
fi

echo "Atualizando target host=${TARGET}"
declare dummy
if [[ "${APP_FORCE_INTERACTIVE}" == '1' ]]; then
    #shellcheck disable=2034
    read -p "Enter para confirmar: <cr>" -r dummy
fi

remotePath="/tmp/patriot/"
DEST_HOST_PATH="${SSH_USER}@${TARGET}:${remotePath}"

echo "atualizando scripts no dispositivo remoto..."
#Avoid rsync host key verification error
sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "$SSH_USER"@"$TARGET" "mkdir -p ${remotePath}"

#Copying files
echo "rsync -avz -e ssh $APP_ROOT_PATH/src/ ${DEST_HOST_PATH}"
sendFilesToHost dummy "$APP_ROOT_PATH/src/" "$remotePath" "$TARGET" "$SSH_USER" "$SSH_PASSWORD"
sendFilesToHost dummy "$APP_ROOT_PATH/.env" "$remotePath" "$TARGET" "$SSH_USER" "$SSH_PASSWORD"
sendFilesToHost dummy "$APP_ROOT_PATH/.env.dev" "$remotePath" "$TARGET" "$SSH_USER" "$SSH_PASSWORD"
sendFilesToHost dummy "$APP_ROOT_PATH/.secret" "$remotePath" "$TARGET" "$SSH_USER" "$SSH_PASSWORD"
sendFilesToHost dummy "$APP_ROOT_PATH/.env.linux" "$remotePath" "$TARGET" "$SSH_USER" "$SSH_PASSWORD"
sendFilesToHost dummy "$APP_ROOT_PATH/lib/" "$remotePath" "$TARGET" "$SSH_USER" "$SSH_PASSWORD"

# sshpass -p "$SSH_PASSWORD" rsync -avz -e ssh "$APP_ROOT_PATH/src/" "${DEST_HOST_PATH}"
# sshpass -p "$SSH_PASSWORD" rsync -avz -e ssh "$APP_ROOT_PATH/.env" "${DEST_HOST_PATH}"
# sshpass -p "$SSH_PASSWORD" rsync -avz -e ssh "$APP_ROOT_PATH/.secret" "${DEST_HOST_PATH}"
# sshpass -p "$SSH_PASSWORD" rsync -avz -e ssh "$APP_ROOT_PATH/.env.dev" "${DEST_HOST_PATH}"
# sshpass -p "$SSH_PASSWORD" rsync -avz -e ssh "$APP_ROOT_PATH/.env.linux" "${DEST_HOST_PATH}"
