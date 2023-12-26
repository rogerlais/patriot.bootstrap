#!/bin/bash

function debug_show_vars() {
    #Mostra as variáveis de ambiente que iniciam com APP_ ou GLOBAL_ ou TEST_ apenas se o valor de APP_DEBUG for 1
    #printenv | sort -f | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"
    #Test if not empty and if greater than 0
    if [[ -n "${APP_DEBUG_LEVEL}" ]] && [[ "${APP_DEBUG_LEVEL}" -gt 0 ]]; then
        #if [[ $APP_DEBUG_LEVEL -gt 0 ]]; then
        echo "Variáveis de ambiente:"
        #env | sort -f | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"  #!bash > 4
        #env -0 | sort -z | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"  #!bash > 4
        printenv | sort -f | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"
    fi
}

function loadEnv() {

    if [ -r "$1" ]; then
        echo "Carregando env: $1 ..." | slog 7
        chmod +x "$1"
        set -o allexport
        #shellcheck source=/dev/null
        source "$1"
        set +o allexport
    else
        echo "Arquivo \"$1\" não pode ser lido" | slog 5
    fi

}

function process_env() {
    #Realiza o processamento da carga dos arquivos .env referenciados pelo valor de ${env:APP_ENVS} na ordem inversa de aparecimento, localizados no caminho dado por $!
    #Caso $1 seja nulo, o diretório corrente é usado
    local rootpath="$1"
    shift
    local envName="$1"
    if [[ -n "${envName}" ]]; then
        envSuffix=".$(echo "$envName" | tr '[:upper:]' '[:lower:]')"
        if [[ "${envSuffix}" == *'.prod'* ]]; then
            envSuffix=''
        fi
    else
        envSuffix=''
    fi
    if [[ -z "${rootpath}" ]]; then
        rootpath=${PWD}
    fi

    parts='.env .secret' #* entradas padrões para o caso de nenhum ser informada
    #local -i i
    for part in $parts; do
        local envFile
        if [ "$(echo "$part" | cut -c1)" = "." ]; then
            #* começando com . -> nome original
            envFile=$(realpath "${rootpath}/${part}")
        else
            #* sem começar com , -> garante extensão esperada
            if [[ "${parts[$i]%%/}" == *'.env' ]]; then
                envFile="${rootpath%%/}/${parts[$i]}"
            else
                envFile="${rootpath%%/}/${parts[$i]}.env"
            fi
        fi
        echo "Processando arquivo de ambiente: ${envFile}${envSuffix}"
        loadEnv "${envFile}${envSuffix}"
    done
}

function array_push() {
    eval "$1=\"\$$1 \$2\""
}

function download_repo() {
    #url="https://${APP_GIT_SERVER}/api/v4/projects/${APP_PROJECT_ID}/repository/archive.zip?private_token=${APP_TOKEN_STR}?ref=main"
    if [[ ${APP_GIT_PROVIDER} == 'gitlab' ]]; then
        url="https://${APP_GIT_SERVER}/api/v4/projects/${APP_PROJECT_ID}/repository/archive.zip?private_token=${APP_TOKEN_STR}"
    else
        #Using github
        url="https://${APP_GIT_SERVER}/${APP_PROJECT_ID}/zip/refs/heads/main"
    fi
    
    echo "atualizando scripts no dispositivo remoto via repostório git..."
    #repeat until success
    retries=0
    success=1
    echo "url=$url"
    while [ $success -ne 0 ]; do
        response_code=$(curl -k -s -o patriot-alpine.zip -w "%{http_code}" -L "$url")
        if $? -ne 0; then
            echo "Erro ao baixar o arquivo zipado do repositório git"
            break
        fi
        # shellcheck disable=SC2086
        if [ "$response_code" -eq 200 ]; then
            echo "Download bem-sucedido (HTTP 200)."
            success=0
        else
            echo "Falha no download (HTTP $response_code). Tentando novamente..."
            success=1
            sleep 5
        fi
        if [ "$success" -eq 0 ]; then
            break
        fi
        retries=$((retries + 1))
        echo "Erro ao baixar o arquivo zipado do repositório gitlab #(${retries})"
        if [[ $retries -gt 10 ]]; then
            echo "Erro fatal ao baixar o arquivo zipado do repositório gitlab"
            break
        fi
        sleep 5
    done
}

if [[ "${ENV_NAME}" == "dev" ]]; then
    echo "DEVELOPMENT mode"
    export APP_DEV_MODE=1
else
    #todo:design: include another envs, if necessary
    echo "PRODUCTION mode"
    export APP_DEV_MODE=0
fi

#Filter and assign command line arguments
#declare -a FREE_ARGS
# shellcheck disable=SC2034
FREE_ARGS=''
for arg in "$@"; do
    # shellcheck disable=SC2143
    if [ "$(echo "$arg" | grep -q '=')" ]; then
        # Teste se a variável de ambiente APP_DEV_MODE está definida
        if [ "${APP_DEV_MODE}" = '1' ]; then
            echo "VALOR -> ${arg}"
        fi
        eval "INPUT_ARG_$arg"
    else
        echo "argumento livre( ${arg} )"
        array_push FREE_ARGS "$arg"
    fi
done
# Para acessar os elementos separados por espaços:
# for element in $FREE_ARGS; do
#    echo "Elemento: $element"
#-done

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
if [[ -d "${APP_ROOT_PATH}/lib" ]]; then
    #Test if APP_ROOT_PATH has a ./lib subfolder to signatura for remote execution outside development environment
    APP_LIB_DIR=$(realpath "${APP_ROOT_PATH}/lib")
    APP_DBG_DIR=$(realpath "${APP_ROOT_PATH}/lib/debug")
else
    APP_LIB_DIR=$(realpath "${APP_ROOT_PATH}/../../lib/")
    APP_DBG_DIR=$(realpath "${APP_ROOT_PATH}/../../lib/debug")
fi
export APP_ROOT_PATH
export APP_DBG_DIR
export APP_LIB_DIR
export APP_ENV_NAME

# shellcheck source=/dev/null
#source "${APP_LIB_DIR}/utilsFuncs.sh"
# shellcheck source=/dev/null
#source "${APP_LIB_DIR}/cfgFuncs.sh"
source "${APP_LIB_DIR}/basiclog.sh"

#Loads vars from .env files
process_env "$APP_ROOT_PATH" "$APP_ENV_NAME"

#Show vars if debug mode
debug_show_vars

#Download repo from git
if download_repo; then
    echo "Download do repositório git bem-sucedido."
    echo "${APP_ROOT_PATH}"
    echo "Usando ${APP_ROOT_PATH}/tmp "
    echo "Usando $(realpath "${APP_ROOT_PATH}/tmp")"
    APP_TMP=$(realpath "${APP_ROOT_PATH}/tmp")
    mkdir -p "${APP_TMP}" >/dev/null 2>&1
    if unzip -o patriot-alpine.zip -d "$APP_TMP" >/dev/null; then
        #take first directory name at unziped file
        #leaf=$(find "$APP_TMP" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -n 1)
        leaf="$( (find "$APP_TMP" -mindepth 1 -maxdepth 1 -type d) | head -n 1)"
        #APP_TMP="${APP_TMP}/${leaf}"
        #echo "APP_TMP: ${APP_TMP}"
        echo "leaf: ${leaf}"
        cp .env "${leaf}/.env"
        cp .secret "${leaf}/.secret"
        cp .id "${leaf}/.id"
        #* execute oob_install.sh
        if [[ -f "${leaf}/oob_install.sh" ]]; then
            echo "executing oob_install.sh"
            chmod +x "${leaf}/oob_install.sh"
            ash "${leaf}/oob_install.sh" "$@" &
        else
            echo "oob_install.sh not found!!!"
        fi
    fi
else
    echo "Falha no download do repositório git."
    exit 1
fi

echo "Fim do script install"