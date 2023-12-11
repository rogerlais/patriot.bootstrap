#!/bin/bash

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

function read_confirm_input() {
	local retf="$1"
	local prompt="$2"
	local defValue="$3"
	local isPrivate="$4"
	[[ -z "$isPrivate" ]] && isPrivate=0
	if [[ -n $defValue ]]; then #Valor default existe
		local promptAnswer
		if [[ isPrivate -ne 0 ]]; then
			get_prompt_confirmation promptAnswer "$prompt - Confirma o uso do valor(********)?" "SN"
		else
			get_prompt_confirmation promptAnswer "$prompt - Confirma o uso do valor($defValue)?" "SN"
		fi
		if [[ 'Ss' == *"$promptAnswer"* ]]; then
			retf=$defValue
		else
			if [[ isPrivate -ne 0 ]]; then
				read -r -s -p "$prompt" retf
				echo #Volta a linha omitida pelo prompt não ecoado
			else
				read -r -p "$prompt" retf
			fi
		fi
	fi
	printf -v "$1" "%s" "$retf"
}

function read_domain_credential() {
	local retf="$1"
	local retfInner
	if [[ -n $APP_DOMAIN_ADM_ACCOUNT && -n $APP_DOMAIN_ADM_ACCOUNT_PWD ]]; then
		get_prompt_confirmation retfInner "Deseja usar as credenciais salvas para ( $APP_NAS_DOMAIN\\$APP_DOMAIN_ADM_ACCOUNT )?" 'SN'
		[[ 'sS' == *"$retfInner"* ]] && return 0
	fi
	local userInput
	read_confirm_input userInput "Informe conta com permissão de ingresso no domínio $APP_NAS_DOMAIN:" "$APP_DOMAIN_ADM_ACCOUNT" "0"
	local pwdInput
	read_confirm_input pwdInput "Informe a senha para( $APP_NAS_DOMAIN\\$userInput ):" "$APP_DOMAIN_ADM_ACCOUNT_PWD" "1"
	if [[ -n $userInput && -n $pwdInput ]]; then
		APP_DOMAIN_ADM_ACCOUNT="$userInput"
		APP_DOMAIN_ADM_ACCOUNT_PWD="$pwdInput"
		retf=0
	else
		echo "Credenciais inválidas. Tentar novamente?"
		retf=1
	fi
	printf -v "$1" "%d" "$retf"
}

function read_NAS_credential() {
	local retf="$1"
	local retfInner
	if [[ -n $APP_NAS_ADM_ACCOUNT && -n $APP_NAS_ADM_ACCOUNT_PWD ]]; then
		get_prompt_confirmation retfInner "Deseja usar as credenciais salvas para a conta local\ADM do NAS?" "SN"
		[[ 'Ss' == *"$retfInner"* ]] && return 0
	fi

	local userInput
	read_confirm_input userInput "Informe a conta ADM local em $HOSTNAME:" "$APP_NAS_ADM_ACCOUNT" "0"

	local pwdInput
	read_confirm_input pwdInput "Informe a senha da conta ($HOSTNAME\\$userInput):" "$APP_NAS_ADM_ACCOUNT_PWD" "1"

	if [[ -n $userInput && -n $pwdInput ]]; then
		APP_NAS_ADM_ACCOUNT="$userInput"
		APP_NAS_ADM_ACCOUNT_PWD="$pwdInput"
		echo "read NAS Credential saida com user = $APP_NAS_ADM_ACCOUNT senha = $APP_NAS_ADM_ACCOUNT_PWD"
		retf=0
	else
		echo "Credenciais inválidas. Tentar novamente?"
		retf=1
	fi
	printf -v "$1" "%d" "$retf"
}

function read_device_id() {
	local retf="$1"
	local -i deviceId=0
	if [ -n "$APP_DEVICE_ORDER_ID" ]; then
		get_prompt_confirmation retfInner "Deseja usar o valor padrão para o índice do dispositivo(${APP_DEVICE_ORDER_ID})?" 'SN'
		[[ 'sS' != *"$retfInner"* ]] && APP_DEVICE_ORDER_ID=0
		[[ $APP_DEVICE_ORDER_ID != 0 ]] && retf=0 || retf=1
	fi
	while [[ "$APP_DEVICE_ORDER_ID" -lt "1" ]]; do
		echo -n "Digite índice do dispositvo no contexto da unidade: "
		read -r deviceId
		if [ -n "$deviceId" ]; then
			if [[ "$deviceId" -ge "1" ]]; then
				APP_DEVICE_ORDER_ID=$deviceId
				retf=0
			else
				echo "Índice( $deviceId ) é inválido."
			fi
		else
			slog 2 "Coleta de dados cancelada pelo usuário"
			retf=1 #reporta erro
		fi
	done
	printf -v "$1" "%d" "$retf"
}

function read_local_id() {
	local retf="$1"
	local -i localId=0
	if [ -n "$APP_LOCAL_ID" ]; then
		echo "Valor da unidade ( $APP_LOCAL_ID ) pré-carregado do ambiente" | slog 6
		if [ "$(get_localId_class "$APP_LOCAL_ID")" -gt "0" ]; then #* ret > 0 -> ou zona(1) ou NVI(2)
			retf=0
		else
			if [ "$retf" -lt 0 ]; then
				echo "Valor carregado inválido( $APP_LOCAL_ID )."
				retf=1
			fi
		fi
	else
		while [[ "$(get_localId_class "$APP_LOCAL_ID")" -lt "1" ]]; do
			echo -n "Digite identificador da unidade Eleitoral: "
			read -r localId
			if [ -n "$localId" ]; then
				if [[ "$(get_localId_class "$localId")" -gt "0" ]]; then
					APP_LOCAL_ID=$localId
					retf=0
				else
					echo "Identificador( $localId ) é inválido."
				fi
			else
				slog 2 "Coleta de dados cancelada pelo usuário"
				retf=1 #reporta erro
			fi
		done
	fi
	printf -v "$1" "%d" "$retf"
}

function get_prompt_confirmation() {
	local ret_prompt_confirmation="$1"
	local screenPrompt="$2"
	local availbleOptions="$3"
	echo -n "${screenPrompt}[$availbleOptions]:" >&2 #não inserir na saída do método
	ret_prompt_confirmation=$(get_key_press "$availbleOptions")
	echo "$ret_prompt_confirmation"
	printf -v "$1" "%s" "$ret_prompt_confirmation"
}

function get_key_press() {
	local validCharSet="$1"
	local defaultResult="$2"
	local caseSensitive="$3"
	local ret_get_key_press=''
	while [[ -z $ret_get_key_press ]]; do
		read -rsn1 ret_get_key_press
		if [[ ! $caseSensitive ]]; then
			#validCharSet=${validCharSet^^}  #*BASH > 4
			validCharSet=$(tr '[:lower:]' '[:upper:]' <<<"${validCharSet}") #* BASH < 4
			#ret_get_key_press=${ret_get_key_press^^}
			ret_get_key_press=$(tr '[:lower:]' '[:upper:]' <<<"${ret_get_key_press}")
		fi
		if ! [[ "$validCharSet" == *"$ret_get_key_press"* ]]; then #Valor fora do conjunto -> tentar de novo caso inexista default
			ret_get_key_press=''
		fi
		if [[ -z $ret_get_key_press && -n $defaultResult ]]; then
			ret_get_key_press=${defaultResult}
		fi
	done
	echo "$ret_get_key_press"
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

function create_volumes() {
	#recebe o caminho para o json com os dados dos volumes
	local -i retf="$1"
	local jsonfile="$2"
	local createLimit="$3"
	local -i ret_create_volumes volCount volIdx shareIdx volType
	local alias shares size primaryShareName

	ret_create_volumes=$(test_json "${jsonfile}")
	if [[ ret_create_volumes -ne 0 ]]; then
		echo "Parser do JSON com os dados dos volumes não poder ser lido( $ret_create_volumes )" | slog 3
		return "$ret_create_volumes"
	fi

	[ -z "$createLimit" ] && createLimit=1024
	[ "$createLimit" == "0" ] && createLimit=1024
	echo "Volumes limitados a ( $createLimit )" | slog 7
	volCount=$(jq "length" "$jsonfile")
	if [[ volCount -gt createLimit ]]; then
		volCount=$createLimit
	fi
	echo "Serão criados ( $volCount ) volumes" | slog 7
	for ((volIdx = 0; volIdx < volCount; volIdx++)); do
		alias=$(jq -r ".[$volIdx].alias" "$jsonfile")
		volType=$(jq -r ".[$volIdx].lv_type" "$jsonfile")
		shares=$(jq ".[$volIdx].shares" "$jsonfile")
		size=$(jq -r ".[$volIdx].size" "$jsonfile")
		primaryShareName=$(echo "$shares" | jq -r ".[0].name")
		echo "Volume Index<$((volIdx + 1))> - Volume alias<$alias> - Volume size<$size> - Volume type<$volType> Principal sharename<$primaryShareName>" | slog 7
		echo "Shares: $shares" | slog 7
		echo "Criando volume <$((volIdx + 1))>" | slog 7
		echo "Criando volume $((volIdx + 1))/${volCount}"
		create_vol "$alias" "$primaryShareName" "$size" "$volType"
		if [[ $? ]]; then
			shareCount=$(echo "$shares" | jq "length")
			if [[ shareCount -gt 1 ]]; then
				echo "Adicionando compartilhamentos secundários..." | slog 6
				for ((shareIdx = 1; shareIdx < shareCount; shareIdx++)); do #Salta o indice 0 por ter sido feito junto com volume acima
					secShareName=$(echo "$shares" | jq -r ".[$shareIdx].name")
					echo "Novo compartilhamento secundário: $secShareName"
					create_secondary_share ret_create_volumes "$secShareName" "$alias" #convert volumeID base 0 to 1
				done
			fi
		else
			echo "Erro criando volume $alias" | slog 2
		fi
	done
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

function get_files_list_b3() {
	local path="$2"
	local fileExtension="$3"
	if ! collect=$(find "$path" -maxdepth 1 -printf "%f\n" 2>/dev/null); then #Versões do bash/find comportamentos distintos
		collect=$(find ./ -maxdepth 1 -print 2>/dev/null)
	fi
	if [ $? ]; then
		while IFS='' read -r line; do
			name="${line}" #name="${line#*.}"
			if [[ $name =~ .*\.$fileExtension ]]; then
				item="$(
					cd "$(dirname "$path/$name")" || exit
					pwd
				)/$(basename "$path/$name")" #test: linha original acima era -> cd "$(dirname "$path/$name")"
				G_RET_A+=("$item")
			fi
		done <<<"$collect"
	else
		slog 3 "Erro de coleta de arquivos - retorno inválido"
		G_RET_A=()
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

function convertShortLongByteSize() {
	#Dada string "human-readble" de capacidade, converte para o valor inteiro correlato
	#exemplo "123.5 TB" --> 126.464.000.000.000
	#para rodar em bash 3, precisa-se dois vetores(complicou um pouco)
	SFX='YZEPTGMK'                  #Sufixos dos valoresy-yota, z-zeta, p-peta....k-kilo
	SFX_MULT=(24 21 18 15 21 9 6 3) #multiplicadores vinculados
	input=$(echo "$1" | tr -d ' 	') #trim spaces & tabs
	suffix="${input: -1}"           #last char, must be discard if "B"(ytes)
	length=${#input}
	if [[ "$suffix" == "B" ]]; then
		suffix="${input: -2:1}"
		number="${input:0:length-2}" #load values, ignore sufix(2 chars)
	else
		number="${input:0:length-1}" #load values, ignore sufix(1 char)
	fi
	pos=$(awk -v b="$suffix" -v a="$SFX" 'BEGIN{print index(a,b)}')
	num=$(awk "BEGIN {printf \"%f\",1024*${number}*(10 ^ ${SFX_MULT[${pos}]})}") #awk no qnap estoura para decimais -> usar float
	printf "%f\n" "${num}"
}

function get_localId_class() {
	#Valida a entrada do identificador da unidade. Valor negativo -> invalido
	if [[ -z "${1}" ]]; then
		echo "0" #Valor indefinido ou todos
	else
		local localId=$(($1))                      #int -> without quotation marks
		if ((localId >= 1 && localId <= 79)); then #1 a 79 - por simplicidade neste momento. O real é um pouco diferente
			echo "1"
		elif ((localId >= APP_MIN_NVI_ID && localId <= APP_MAX_NVI_ID)); then #NVIs conhecidos
			echo "2"
		else # para todos os demais valores, erro
			echo "-1"
		fi
	fi
}

function convertLongShortByteSize() {
	#$1 = retorno da mantissa do tamanho
	#$2 = retorno do expoente em 'X'B
	local size="$3"      #Valor inteiro grande a ser convertido para a forma curta
	local precision="$4" #Quantidade de dígitos( 0 a 2 aceitos) - opcional
	local base="$5"      #Base de conversão(1000 ou 1024 aceitos) - opcional
	if ! [[ $precision ]]; then
		precision=2
	fi
	if ! [[ $base ]]; then
		base=1024
		factor=1000
	elif ! [ "$base" == 1000 ]; then
		factor=1024
	fi
	declare -a grade=('' K M G T P E Z Y)
	declare suffix="${grade[0]}B"
	for ((i = 0; i <= 8; i++)); do
		factor=$((factor * (base ** i)))
		q=$((size / factor))
		if [[ q -le 999 ]]; then
			suffix="${grade[${i} + 1]}B"
			printf -v "$2" "%s" "$suffix" #retorno expoente
			#qts 5.1 sem bc, se vira com awk
			out=$(awk -v size="$size" -v factor="$factor" -v CONVFMT=%.17g "BEGIN{ print (1000*size/factor) }")
			printf -v "$1" "%.0f" "$out" #retorno mantissa
			break
		fi
	done
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

	echo "Procurando envfiles em \"$rootpath\"..." | slog 7
	local -a parts
	if [[ -n "${APP_ENVS}" ]]; then
		local noQuotes
		noQuotes="${APP_ENVS//\'/}" #! Como remover caracter (') foi complicado !PQP!
		IFS=":" read -r -a parts <<<"$noQuotes"
	else
		parts=('.env' '.secret') #* entradas padrões para o caso de nenhum ser informada
		echo "Buscando envFiles padrões(.env+.secret)" | slog 7
	fi
	local -i i
	for ((i = ${#parts[@]} - 1; i >= 0; i--)); do
		local envFile
		if [[ "${parts[$i]%%/}" == $"."* ]]; then
			#* começando com . -> nome original
			envFile="${rootpath%%/}/${parts[$i]%%/}"
		else
			#* sem começar com , -> garante extensão esperada
			if [[ "${parts[$i]%%/}" == *'.env' ]]; then
				envFile="${rootpath%%/}/${parts[$i]}"
			else
				envFile="${rootpath%%/}/${parts[$i]}.env"
			fi
		fi
		# if [[ "${parts[$i]%%/}" == "." ]]; then
		# 	envFile="${rootpath%%/}/.env"
		# else
		# 	envFile="${rootpath%%/}/${parts[$i]}.env"
		# fi
		echo "Processando arquivo de ambiente: ${envFile}${envSuffix}"
		loadEnv "${envFile}${envSuffix}"
	done
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

function debug_show_vars() {
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

function wait_resync() {
	local -i _wait_resync
	SECONDS=0
	if [[ "$APP_SKIP_POOL_RESYNC" -eq "1" ]]; then
		echo "Espera de resincronização do pool ignorada pela configuração do ambiente." | slog 6
		_wait_resync=0
	else
		if [[ $APP_IS_DEV_ENV != 0 ]]; then
			[ "$TEST_VALUE_RESYNC_OK" == "1" ] && _wait_resync=0 || _wait_resync=1 #Teste se pula a espera(apenas no modo DEV)
			progressFile="$PWD/debug/sync_completed.txt"
		else
			#todo:future: Melhorar captura do caminho do arquivo de progresso
			progressFile=/sys/block/md1/md/sync_completed
		fi

		if [ "$_wait_resync" -eq "0" ]; then
			echo "Espera simulada bypassed(env:TEST_VALUE_RESYNC_OK)" | slog 7
		else
			echo "Aguarde a resincronização do RAID-1."
			echo "Tal processo levará algumas horas. Sugerimos fazer outra coisa por enquanto!"
			if [ -r "$progressFile" ]; then
				./adjust_sync_speed.sh 0 #Aumenta a prioridade da sincronização
				while true; do
					local -a parts
					content=$(tr <"$progressFile" '[:upper:]' '[:lower:]')
					if [[ "$content" == 'none' ]]; then
						_wait_resync=0
						break
					else
						IFS='/' read -r -a parts <<<"$content"
						if [[ "${#parts[@]}" -ne 2 ]]; then
							break
						else
							current="${parts[0]}"
							total="${parts[1]}"
							ProgressBar "$current" "$total"
						fi
					fi
					sleep $((5 * APP_MIN_TIME_SLICE))
				done
				./adjust_sync_speed.sh 1
			else
				echo "Arquivo com informações de progresso não podem ser lidas($progressFile)"
			fi
		fi
	fi
	ProgressBar "100" "100"
	echo
	echo "DURAÇÃO DA SINCRONIZAÇÃO = $((SECONDS / 3600))h $(((SECONDS / 60) % 60))m $((SECONDS % 60))s"
	printf -v "$1" "%d" "$_wait_resync"
}

function resolve_target_address() {
	#Take a string, test if is a valid IP, if not, try to resolve as hostname
	#Return 0 if success, 1 if error
	#todo: Não testada
	local target="$1"
	local -i ret_resolve_target_addres

	# shellcheck disable=SC2317

	if [[ -z "$target" ]]; then
		echo "IP inválido( $target )"
		ret_resolve_target_addres=1
	else
		ret_resolve_target_addres=0
		if ! [[ "${target}" == *"."* ]]; then
			#Test if a integer between 1 and 254
			if [[ "${target}" =~ ^[0-9]+$ ]]; then
				if [[ "${target}" -lt 1 ]] || [[ "${target}" -gt 254 ]]; then
					echo "IP inválido( $target )"
					ret_resolve_target_addres=1
				else #Add prefix to IP
					target="${APP_PRIVATE_VLAN/'0/24'/"$target"}"
				fi
			else
				echo "IP inválido( $target )"
				ret_resolve_target_addres=1
			fi
		else
			dots=$(echo "$target" | grep -o '\.' | wc -l)
			if [[ "${dots}" -ne 3 ]]; then
				echo "IP inválido( $target )"
				ret_resolve_target_addres=1
			fi
		fi
	fi
	printf -v "$1" "%d" "$ret_resolve_target_addres"
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

function sendFilesToHost() {
	#Envia arquivos para o host remoto
	#Parametros:
	#	$1 - caminho local
	#	$2 - caminho remoto
	#	$3 - host remoto
	#	$4 - usuário remoto
	#	$5 - senha remota
	#	$6 - tipo de envio(0 - auto, 1 - scp, 2 - rsync, 3 - tar)
	local -i retf="$1"
	local localPath="$2"
	local remotePath="$3"
	local remoteHost="$4"
	local remoteUser="$5"
	local remotePwd="$6"
	local sendType="$7"

	#todo:bug APP_LAST_SEND_TYPE dont persist. Without solution, take loop at begining first

	#test previous way to send, using APP_LAST_SEND_TYPE
	if [[ -z "$sendType" ]]; then
		sendType=$((APP_LAST_SEND_TYPE))
	fi
	#remount recursive call to self passing sendType as parameter incremented by 1
	if [[ "$sendType" -eq "0" ]]; then
		sendType=1
		sendFilesToHost ret_sendFilesToHost "$localPath" "$remotePath" "$remoteHost" "$remoteUser" "$remotePwd" $((sendType))
		retf=$?
		if [[ "$retf" -ne "0" ]]; then
			export APP_LAST_SEND_TYPE=(sendType)
		fi
	else

		#make a loop to try all send types
		for ((i = 1; i < 4; i++)); do
			sendType=$((i))
			#switch to sendType 
			case $((sendType)) in
			1)
				#1 - scp
				sshpass -p "$remotePwd" scp -r "$localPath" "$remoteUser"@"$remoteHost":"$remotePath"
				retf=$?
				;;
			2)
				#rsync
				sshpass -p "$remotePwd" rsync -avz -e ssh "$localPath" "$remoteUser"@"$remoteHost":"$remotePath"
				retf=$?
				;;
			3)
				#tar
				# shellcheck disable=SC2029
				sshpass -p "$remotePwd" tar -cvzf - "$localPath" | ssh "$remoteUser"@"$remoteHost" "tar -xvzf - -C ${remotePath}"
				retf=$?
				;;
			*)
				echo "Tipo de envio inválido($sendType)"
				retf=1
				break
				;;
			esac
			if [[ "$retf" -eq "0" ]]; then
				export APP_LAST_SEND_TYPE=(sendType)
				break
			fi
		done
	fi
	#Register last successfull send type
	export APP_LAST_SEND_TYPE
	printf -v "$1" "%d" "$retf"
}
