#!/bin/bash

#!   ******** ALPINE LIB  *******

#todo:future: Implementar leitura dos parametros dos discos e não pedir ao usuário
#hdparm -I /dev/sda para pegar atributos do disco

# shellcheck source=/dev/null
if [[ -z "${APP_LIB_DIR}" || ! -d "${APP_LIB_DIR}" ]]; then
	echo "Caminho para a biblioteca APP_LID_DIR( ${APP_LIB_DIR} ) inválido" >&2
fi
source "${APP_LIB_DIR}/basiclog.sh" #Premiss same dir

function get_scriptname() {
	#Returns the base name from script that started this process
	#todo:lib: Move to lib
	basename "$(test -L "$0" && readlink "$0" || echo "$0")"
}

function setDeviceName() {
	local retf="$1"
	local newName="$APP_NAS_HOSTNAME" #was an argument, now uses global
	local curName
	curName=$(getcfg system "Server Name")
	echo "Novo nome=($newName) - Nome antigo=($curName)"
	if [ "$newName" != "$curName" ]; then
		echo "Alterando o nome do dispositivo para ($newName)..."
		setcfg system "Server Name" "$newName" #* em testes, tal chamada aceita praticamente tudo sem gerar erro
		#todo:future: informar no comentário sobre este servidor para exibição, demais dados, como cidade, etc(agora usando apenas valor de newName)
		setcfg system "Server Comment" "$newName"
		retf=$?
		if [ $retf -ne 0 ]; then
			echo "Falha renomeando dispositivo - erro: $retf"
		else
			echo "Nome do dispositivo alterado de ($curName) para ($newName)"
		fi
	else
		slog 6 "Nome atual já corretamente atribuído para: $newName"
		retf=0
	fi
	printf -v "$1" "%d" $retf
}

function test_json() {
	#todo:lib: levar para lib o teste de json( 0 - sucesso, 1 - falha, 4 - inválido)
	#Ref.: https://stackoverflow.com/questions/46954692/check-if-string-is-a-valid-json-with-jq
	local jsonfile="$1"
	if ! [ -r "$jsonfile" ]; then
		echo "Caminho para os dados dos cvolumes ($jsonfile) não pode ser lido!" | slog 3
		return 1
	fi
	echo "$(<"$jsonfile")" | jq -e . >/dev/null 2>&1 || echo "${PIPESTATUS[1]}"
}

function checkTolerancePercent() {
	#Avalia se o valor de comparação está dentro do de referência +/- o percentul informado
	local reference=$1
	local compValue=$2
	local pmargin=$3 ## Deve ser valor inteiro entre 1 e 99
	maxV=$((reference + (pmargin * reference / 100)))
	minV=$((reference - (pmargin * reference / 100)))
	if [[ $compValue -gt $maxV ]]; then
		return 1
	elif [[ $compValue -lt $minV ]]; then
		return 1
	else
		return 0
	fi
}

function get_abs_value() {
	#Calcula o valor absoluto datos o total e o percentual
	#Valores flutuantes com ponto como separador
	pool_size="${1}"
	vol_percent="${2}"
	awk "BEGIN {printf \"%d\",${pool_size}*${vol_percent}/100}" #Saida com inteiro livre
}

function truncToInt() {
	#trunca valor flututante para inteiro
	echo "${1%.*}"
}

function get_root_login() {
	#Passar texto plano para esta rotina de autenticação
	local login=$2
	local pwd=$3
	#Chamada para a autenticação do cliente na CLI
	qcli -l user="$login" pw="$pwd" saveauthsid=yes #* é gerado um sid aqui, talvez possa ser utils depois
	printf -v "$1" "%d" "$?"
}

function process_env_() {
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
    	#todo:remover echo "Part: $part"
		local envFile
		if [[ "${part}" == $"."* ]]; then
			#* começando com . -> nome original
			envFile="${rootpath%%/}/${part%%/}"
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

function loadEnv_() {

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

function debug_show_vars_() {
	#Mostra as variáveis de ambiente que iniciam com APP_ ou GLOBAL_ ou TEST_ apenas se o valor de APP_DEBUG for 1
	if [[ $APP_DEBUG_LEVEL -gt 0 ]]; then
		echo "Variáveis de ambiente:"
		#env | sort -f | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"  #!bash > 4
		#env -0 | sort -z | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"  #!bash > 4
		env | sort -f | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"
	fi
}

function ProgressBar() {
	((currentState = $1))
	((totalState = $2))
	_progress=$((currentState * 100 / totalState))
	((_done = $((_progress * 4)) / 10))
	((_left = 40 - _done))
	# Build progressbar string lengths
	_done=$(printf "%${_done}s")
	_left=$(printf "%${_left}s")
	printf "\rProgresso : [${_done// /#}${_left// /-}] ${_progress}%%"
}

function complete_target_address() {
	#Take a string partially filled with IP address, complete with the suffix based at the current VLAN
	#Return 0 if success, 1 if error
	local i retf="$1"
	local target="$2"
	if [[ -z "$target" ]]; then
		echo "IP inválido( $target )"
		retf=''
	else
		if ! [[ "${target}" == *"."* ]]; then
			#Test if a integer between 1 and 254
			if [[ "${target}" =~ ^[0-9]+$ ]]; then
				if [[ "${target}" -lt 1 ]] || [[ "${target}" -gt 254 ]]; then
					echo "IP inválido( $target )"
					retf=''
				else #Add prefix to IP
					retf="${APP_PRIVATE_VLAN/'0/24'/"$target"}"
				fi
			else
				#try by name
				local resolIP
				resolve_target_address resolIP "$target"
				if [[ -n $resolIP ]]; then
					echo "IP inválido( $target )"
					retf=''
				fi
				dots=$(echo "$target" | grep -o '\.' | wc -l)
				if [[ "${dots}" -ne 3 ]]; then
					echo "IP inválido( $target )"
					retf=''
				fi
			fi
		fi
	fi
	printf -v "$1" "%s" "$retf"
}
