#!/bin/bash

function array_push() {
  eval "$1=\"\$$1 \$2\""  #Separator is blank space only as token to elements
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
#if [[ -z "${INPUT_ARG_rootdir}" ]]; then
#    APP_ROOT_PATH=$(dirname "$0") #"${PWD}" #Root from project as default
#else
#    APP_ROOT_PATH="${INPUT_ARG_rootdir}"
#fi

#Define APP_ENV_NAME global variable
if [[ -n "${INPUT_ARG_env}" ]]; then
    APP_ENV_NAME="${INPUT_ARG_env}" #Using env forced by from command line
else
    APP_ENV_NAME="$ENV_NAME" #using env var from process calling
fi

#take path from this script
APP_ROOT_PATH=$(dirname "$0")
APP_LIB_DIR=$( realpath "${APP_ROOT_PATH}/lib" )
#APP_DBG_DIR=$( realpath './debug' )

# shellcheck source=/dev/null
source "${APP_LIB_DIR}/utilsFuncs.sh"
# shellcheck source=/dev/null
source "${APP_LIB_DIR}/cfgFuncs.sh"

#Loads vars from .env files
process_env "${APP_ROOT_PATH}" "$APP_ENV_NAME"
#Show vars if debug mode
debug_show_vars

