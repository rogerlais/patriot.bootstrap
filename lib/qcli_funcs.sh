#!/bin/bash


function switch_simulated_qcli() {
    #!IMPORTANTE: A função abaixo é usada para simular o qcli em ambiente de desenvolvimento
	# shellcheck source=/dev/null
	source "${APP_LIB_DIR}/qcli_simulated.sh"
}

function create_secondary_share() {
	local ret_create_secondary_share=$1
	local sharename=$2
	local volAlias=$3
	local -i ret_create_secondary_share=0
	local -i volID
	get_volume_id_by_alias volID "$volAlias"
	if [[ volID -le 0 ]]; then
		echo "Alias com o nome ($volAlias) não encontrado. para a criação do compartilhamento( $sharename )" | slog 7
		ret_create_secondary_share=1 #Volume não encontrado
	else
		qcli_sharedfolder -i sharename="$sharename" &>/dev/null #Gera erro para sharename invalido -> cria-se
		if [[ $? ]]; then
			echo "Novo comparilhamento secundário em criação $sharename no volume $volID" | slog 6
			qcli_sharedfolder -s sharename="$sharename" volumeID="$volID" &>/dev/null #convert volumeID base 0 to 1
			ret_create_secondary_share=$?
			#todo: validar se chamada acima precisa aguardar processo finalizar
			#*saida comando acima abaixo reproduzida abaixo, omitida no console:
			#Please use qcli_sharedfolder -i, qcli_sharedfolder -u & qcli_sharedfolder -f to check status!
			#!remover na versão final as 3 linhas abaixo
			echo "SAIDA qcli_sharedfolder -i sharename=$sharename"
			qcli_sharedfolder -i sharename="$sharename"
			echo "SAIDA qcli_sharedfolder -u sharename=$sharename"
			qcli_sharedfolder -u sharename="$sharename"
			echo "SAIDA qcli_sharedfolder -f sharename=$sharename"
			qcli_sharedfolder -f sharename="$sharename"
		else
			echo "Sharename ( $sharename ) já existe." | slog 5 #Não gera erro
		fi
	fi
	printf -v "$1" "%d" "$ret_create_secondary_share"
}


function create_pool() {
	#Cria o pool de armazenamento. Sugestão de aguardar a ressincronização, como mostrado no link abaixo
	#https://forum.qnap.com/viewtopic.php?t=137370
	local retf="$1"
	local -i pc
	get_pool_count pc
	if [[ pc -eq 0 ]]; then
		echo "Pool de armazenamento não encontrado. Um novo será criado"
		echo "Esta operação pode demorar alguns minutos..."
		#Parece boa pática por um thresohold. Pendente forma de especificar o valor para o "instantaneo"
		qcli_pool -c diskID=00000001,00000002 raidLevel=1 Stripe=Disabled | slog 6
		retf=$?
		if [ $retf -eq 0 ] && [ "$APP_POOL_THRESHOLD" -ne 0 ]; then
			qcli_pool -t poolID=1 threshold="$APP_POOL_THRESHOLD"
		else
			echo "Falha criação de pool de armazenamento"
		fi
	else
		echo "Discos já fazem parte de um pool de armazenamento." | slog 6
		retf=0
	fi
	printf -v "$1" "%d" "$retf"
}

function get_pool_count() {
	local -i ret_get_pool_count
	ret_get_pool_count=$(qcli_pool -l | sed "2q;d")
	printf -v "$1" "%d" "$ret_get_pool_count"
}

function get_volume_id_by_alias() {
	#Assume que o poolID existe
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local retf="$1"
	local alias=$2
	local response volCount volTable line ret_check_vol

	response=$(qcli_volume -i displayfield=Alias,volumeID)
	volCount=$(echo "$response" | sed -n "2p")
	retf=0 #não encontrado
	if [[ $volCount -gt 0 ]]; then
		volTable=$(tail -n +4 <<<"$response") #pula resumo e cabeçalho da saida
		declare -a entries
		while IFS='' read -r line; do
			entries+=("$line")
		done <<<"$volTable"

		for line in "${entries[@]}"; do
			if [[ "$line" == "$alias "* ]]; then #encontrado no começo da cadeia(nota para o espaço ao final como separador)
				IFS="$(printf '\t ')" read -r -a parts <<<"$line"
				retf="${parts[1]}"
				break
			fi
		done
	fi
	printf -v "$1" "%d" "$retf"
}

function check_vol() {
	#Assume que o poolID existe
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local alias=$2
	local sharename=$3
	local volSize=$4 #180388626432 eg sistema

	local response volCount volTable line ret_check_vol

	response=$(qcli_volume -i displayfield=Alias,volumeID,Capacity,Status)

	ret_check_vol=$VOLUME_INEXISTS #resultado default
	volCount=$(echo "$response" | sed -n "2p")
	if [[ $volCount -le 0 ]]; then
		echo "Pool não possui nenhum volume ainda"
	else
		volTable=$(tail -n +4 <<<"$response") #pula resumo e cabeçalho da saida
		declare -a entries
		while IFS='' read -r line; do
			entries+=("$line")
		done <<<"$volTable"

		for line in "${entries[@]}"; do
			if [[ "$line" == "$alias "* ]]; then #encontrado no começo da cadeia(nota para o espaço ao final como separador)
				slog 7 "Alias encontrado($alias)"
				IFS="$(printf '\t ')" read -r -a parts <<<"$line"
				declare mant=0
				declare bexp=''
				convertLongShortByteSize mant bexp "$volSize"
				if [[ "${parts[3]}" == "$bexp" ]]; then
					checkTolerancePercent "$mant" "${parts[2]}" "5" #cinco e meio porcento
					if [ $? ]; then
						ret_check_vol=$VOLUME_OK #Saida do caminho feliz
					else
						slog 7 "Erro/Tolerância de volume ultrapassado (${parts[1]}) ($mant)"
						ret_check_vol=$VOLUME_DIVERGENT
					fi
				else
					slog 7 "Grandezas divergentes (${parts[2]}) ($bexp)"
					ret_check_vol=$VOLUME_DIVERGENT
				fi
				break
			fi
		done
	fi
	printf -v "$1" "%d" "$ret_check_vol"
}

function get_is_volume_ready() {
	local targetVolID=$2
	local response volTable line
	local -i ret_is_volume_ready=1 #Default é falha de volume
	#todo:critical response while rebuild RAID to status is warning divergs from expected "Ready"
	response=$(qcli_volume -i volumeID="$targetVolID" displayfield=Alias,volumeID,Capacity,Status)
	volTable=$(tail -n +4 <<<"$response") #pula resumo e cabeçalho da saida
	declare -a entries
	while IFS='' read -r line; do
		entries+=("$line")
	done <<<"$volTable"

	for line in "${entries[@]}"; do
		IFS=' ' read -r -a parts <<<"$line"
		if [[ "${parts[1]}" == "$targetVolID" ]]; then #encontrado no começo da cadeia
			if [[ "${parts[4]}" == "Ready" ]]; then       #*Assinatura que o volume está OK!
				ret_is_volume_ready=0
			fi
			break
		fi
	done
	printf -v "$1" "%d" "$ret_is_volume_ready"
}

function wait_volume_ready() {
	local targetVolID=$2
	local -i ret_wait_volume_ready=1 #Assume falha inicial
	if [[ $TEST_VALUE_ALL_VOLUMES_OK ]]; then
		ret_wait_volume_ready=0 #Encutar o teste
	else
		local -i retries=0
		while [[ $ret_wait_volume_ready -ne 0 ]]; do #Equivale a 10 minutos(magic number here)
			get_is_volume_ready ret_wait_volume_ready "$targetVolID"
			echo -n '#'
			sleep "$APP_MIN_TIME_SLICE"
			((retries++))
			if [[ $retries -gt 120 ]]; then
				printf "\nFinalização do volume %s está demorando. Sugerimos aguardar um pouco mais."  "${targetVolID}"
				local promptAnswer
				get_prompt_confirmation promptAnswer "Deseja aguardar mais algum tempo(S/N)?" 'SN'
				if [[ 'Ss' == *"$promptAnswer"* ]]; then
					retries=0
				else
					get_prompt_confirmation promptAnswer "Confirma o cancelamento da espera e prosseguimento para etapa seguinte(S/N)?" 'SN'
					if [[ 'Ss' == *"$promptAnswer"* ]]; then
						printf -v "$1" "%d" "$ret_wait_volume_ready"
						return
					else
						retries=0
					fi
				fi
			fi
		done
		echo '.'
		if [[ $ret_wait_volume_ready ]]; then
			echo "Volume(#$targetVolID) pronto!" | slog 5
		else
			echo "Volume(#$targetVolID) falhou em preparação !!!" | slog 3
		fi
	fi
	printf -v "$1" "%d" "$ret_wait_volume_ready"
}

function create_vol() {
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local alias=$1
	local sharename=$2
	local volSize=$3 #180388626432 eg sistema
	local volType=$4 #lv_type={1|2|3} 1:thin 2:thick 3:static

	local -i ret_create_vol=0 #Valor padrão(sucesso)
	check_vol ret_create_vol "$alias" "$sharename" "$volSize"
	if [[ $ret_create_vol -eq $VOLUME_INEXISTS ]]; then
		slog 5 "Criando o volume($alias), favor aguarde..."
		local cmdOut
		cmdOut=$(qcli_volume -c Alias="$alias" diskID="$diskID" SSDCache=no Threshold="$APP_VOLUME_THRESHOLD" \
			sharename="$sharename" encrypt=no lv_type="$volType" poolID="$poolID" raidLevel=1 \
			Capacity="$volSize" Stripe=Disabled)
		ret_create_vol=$?
		if [[ $ret_create_vol ]]; then
			local targetVolID
			targetVolID=$(echo "$cmdOut" | head -1 | awk '{print $NF}' | tr -d .)
			echo "Aguardando o volume( $targetVolID ) ficar pronto..."
			wait_volume_ready ret_create_vol "$targetVolID"
		fi

		if [[ $ret_create_vol ]]; then
			slog 5 "Volume $alias (ID=$targetVolID) criado com sucesso!"
		else
			echo "Erro fatal criando volume($alias = $targetVolID). Abortando processo..."
			return $ret_create_vol #*DEVE se rvalor abaixo de 10
		fi
	else
		if [[ $ret_create_vol -eq $VOLUME_DIVERGENT ]]; then
			slog 3 "Volume com características divergentes foi encontrado!!"
			return "${VOLUME_DIVERGENT}"
		else #VOLUME_OK
			echo "Volume ($alias) com $volSize bytes de tamanho já existe." | slog 6
		fi
	fi
}

function is_package_installed() {
	local pkgName="$1"
	local pkgStatus qpkg_success
	qpkg_success="[CLI] QPKG $pkgName is installed"
	pkgStatus=$(qpkg_cli -s "$pkgName")
	if [[ "$qpkg_success" == "$pkgStatus" ]]; then
		echo 0
	else
		#echo "Current status = $pkgStatus" >&2
		echo 1
	fi
	unset pkgStatus
}

function install_package() {
	local pkgName="$2"
	local ret_install_package=0 #Assume sucesso
	local -i retries=0
	local pkgStatus=''
	if [[ $(is_package_installed "$pkgName" "$pkgStatus") -ne 0 ]]; then
		pkgStatus=$(qpkg_cli -a "$pkgName") #inicia processo de instalação do pacote
		echo "$pkgStatus" | slog 6
		if ! [[ $APP_IS_DEV_ENV ]]; then
			sleep 10
		else
			sleep 1
		fi
		while [[ "$(is_package_installed "$pkgName" "$pkgStatus")" -ne "0" ]]; do
			local oldStatus="$pkgStatus"
			pkgStatus=$(qpkg_cli -s "$pkgName")
			if [[ "$oldStatus" != "$pkgStatus" ]]; then
				echo "$pkgStatus"
				oldStatus="$pkgStatus"
			fi
			((retries++))
			if [[ $retries -gt 60 ]]; then
				echo "Estouro do tempo de espera para o processo de instalação"
				local promptAnswer
				get_prompt_confirmation promptAnswer "Deseja aguardar mais algum tempo(S/N)?" 'SN'
				if [[ 'Ss' == *"$promptAnswer"* ]]; then
					retries=0 #comecar de novo
				else
					ret_install_package=1 #flag de falha
					echo "Instalação de ($pkgName) abortada pelo usuário.!!!" | slog 3
					break
				fi
			fi
			if ! [[ $APP_IS_DEV_ENV ]]; then
				sleep 5
			else
				sleep 1
			fi
		done
	else
		echo "Pacote $pkgName já está instalado" | slog 5
	fi
	printf -v "$1" "%d" $ret_install_package
}

function get_primary_group() {
	local localID=$2
	local ret_primary_group
	if ((1 <= localID && localID <= 77)); then
		ret_primary_group="setorGzon${localID}"
	elif ((APP_MIN_NVI_ID <= localID && localID <= APP_MAX_NVI_ID)); then
		ret_primary_group="setorGNVI${APP_NVI_MAPPING[((localID - 201))]}"
	fi
	printf -v "$1" "%s" "$ret_primary_group"
}

function authenticate_session() {
	#Esse While serve para um tratamento de erro, ao verificar que o comando não teve sucesso ele solicita o usuário e senha novamente
	local -i ret_authenticate_session=1 #Gera erro para entrada do loop(until para bash daria na mesma)

	while [ $ret_authenticate_session != 0 ]; do
		if [[ -n "${APP_NAS_ADM_ACCOUNT}" && -n "${APP_NAS_ADM_ACCOUNT_PWD}" ]]; then
			#Tenta validar com os valores preexistentes
			get_root_login ret_authenticate_session "${APP_NAS_ADM_ACCOUNT}" "${APP_NAS_ADM_ACCOUNT_PWD}"
			if [[ $ret_authenticate_session == 0 ]]; then
				break
			fi
		fi
		echo -n "Login(ADM) do NAS: "
		read -r APP_NAS_ADM_ACCOUNT
		if [ -n "${APP_NAS_ADM_ACCOUNT}" ]; then
			echo -n "Senha para(\"${APP_NAS_ADM_ACCOUNT}\"): "
			read -ers APP_NAS_ADM_ACCOUNT_PWD
			echo
			if [ -n "${APP_NAS_ADM_ACCOUNT_PWD}" ]; then
				get_root_login ret_authenticate_session "${APP_NAS_ADM_ACCOUNT}" "${APP_NAS_ADM_ACCOUNT_PWD}"
				if [[ $ret_authenticate_session -ne 0 ]]; then
					#Reseta valores anteriores(indiferente da origem)
					APP_NAS_ADM_ACCOUNT=''
					APP_NAS_ADM_ACCOUNT_PWD=''
					echo "Credenciais inválidas!" | slog 6
				fi
			else
				echo "Senha nula, inválida"
			fi
		else
			echo "Login nulo, inválido"
		fi
	done
	slog 5 "Autenticacao feita com sucesso"
	printf -v "$1" "%d" "$ret_authenticate_session"
}

function set_extra_settings() {
	echo "Configurando Data e hora"
	qcli_timezone -s timezone=17 dateformat=1 timeformat=24 timesetting=2 server="${APP_NTP_SERVER}" interval_type=2 timeinterval=7 AMPM_option=PM
	echo "Desativando Horário de Verão" | slog 6
	setcfg system 'enable daylight saving time' FALSE
	if [[ $? ]]; then
		echo "Horário de verão ajustado com sucesso!" | slog 6
	else
		echo "Falha ajustando o horário de verão" | slog 3
	fi
}

function get_volume_config_file() {
	#echo "${APP_LIB_DIR}/volumes.json"
	firstGuess="${PWD%%/}/volumes.json"
	if [ -r "${firstGuess}" ]; then
		echo "${firstGuess}"
	else
		lastGuess="${PWD%%/}/lib/volumes.json"
		if [ -r "${lastGuess}" ]; then
			echo "${lastGuess}"
		else
			slog 3 "Falha coletando arquivo com dados de volumes"
		fi
	fi
}

function first_network_setup() {
	#!<01> Em versão não homologada havia alinha abaixo. Não encontrada documentação a respeito da chamada
	local -i ret
	network_boot_rescan
	ret=$?
	if ! [[ $ret ]]; then
		echo "Retorno do rescan de rede: ${ret}"
	fi

	#todo: Validar alterações globais para a inserção sem erros no domínio
	setcfg "Network" "Domain Name Server 1" "${APP_DNS1}"
	setcfg "Network" "Domain Name Server 2" "${APP_DNS2}"
	setcfg "Network" "DNS type" manual
	setcfg "Samba" "DC List" "${APP_DC_PRIMARY_NAME},${APP_DC_SECONDARY_NAME}"
	setcfg "Samba" "User" "${APP_DOMAIN_ADM_ACCOUNT}" #!Usar apenas o nome sem o dominio

	echo "Realizando ajustes de rede..."

	#Aqui inicia seção de alterações, como esperado, sem documentação...
	#Pelos foruns /etc/config/nm.conf são configurações remontadas a cada boot

	#este mesmo valor indiferentemente
	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "current_default_gateway" interface0
	setcfg -f /etc/config/nm.conf global "current_default_gateway" interface0

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "gateway_policy" 2 #original 1
	setcfg -f /etc/config/nm.conf global "gateway_policy" 2           #original 1

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "disable_dw_updater" 0 #indiferentemente sempre 0
	setcfg -f /etc/config/nm.conf global "disable_dw_updater" 0

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "dns_strict_order" 1 #original 0
	setcfg -f /etc/config/nm.conf global "dns_strict_order" 1           #original 0

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "fixed_gateway1" interface0 #Originalmente nulo
	setcfg -f /etc/config/nm.conf global "fixed_gateway1" interface0

	#Alterações pendentes de testes
	setcfg "System" "Workgroup" "${APP_NAS_NETBIOS_DOMAIN}"
	setcfg "System" "Server Name" "${APP_NAS_HOSTNAME}"

	#todo:extras: Outras entradas divergentes para acesso ao dominio coletadas da referencia manual
	rm /etc/resolv.dnsmasq
	echo "nameserver ${APP_DNS1}" >/etc/resolv.dnsmasq
	echo "nameserver ${APP_DNS2}" >>/etc/resolv.dnsmasq

	#* 1 - D:\Sw\WD\Operations\qnap-config\tmp\new.pos-domain\etc\etc\resolv.dnsmasq com as primeiras linnhas como o modelo abaixo:
	# nameserver 10.12.0.134
	# nameserver 10.12.0.228
	# nameserver 10.12.1.18@eth0
	# nameserver 10.12.1.148@eth0
	#* 1.1 - Opcionalmente eliminar as citadas pela configuração via dhcp

	#* 2 - SNMP
	# Em \mnt\HDA_ROOT\.config\snmpd.conf, seguem as linhas, onde as duas primeiras são alvos de alteração
	# sysName ZPB205NAS01 (*alteração aqui*)
	# syscontact louis@celab1.ee.ntou.edu.tw
	# syslocation keelung
	# rwcommunity public
	# rocommunity public

	#!<02> Em versão não homologada havia alinha abaixo. Idem ao caso <01>
	network_boot_rescan

	echo 'Reiniciando serviços de rede...' | slog 6
	if ! [[ $APP_IS_DEV_ENV ]]; then
		/etc/init.d/network.sh restart | slog 6
	else
		echo "Serviços de rede não reinciados pelo modo de depuração ativo!!!!!!!!!!"
	fi
	printf -v "$1" "%d" "0" #Sem captura de erro possível aqui :-(
}

function test_domain() {
	local retf="$1"
	local _retries="$2"
	local content match
	for ((i = 0; i < _retries; i++)); do
		content=$(tr '[:lower:]' '[:upper:]' <<<"$(qcli_domainsecurity -A)")
		match=$(tr '[:lower:]' '[:upper:]' <<<"$APP_NAS_DOMAIN")
		if [[ $content == *"$match"* ]]; then
			echo "Dispositivo já se encontra no domínio($APP_NAS_DOMAIN)" | slog 7
			retf=0
			break
		else
			echo -e "Resposta de consulta de união ao dominio = \n$content" | slog 7
			retf=1
		fi
		sleep "$APP_MIN_TIME_SLICE"
	done
	printf -v "$1" "%d" "$retf"
}


function set_DNS () {
	setcfg "Network" "DNS type" manual
	setcfg Network 'Domain Name Server' "$APP_DNS1"
	setcfg Network 'Domain Name Server 1' "$APP_DNS1"
	setcfg Network 'Domain Name Server 2' "$APP_DNS2"
}

function set_SambaBaseProps(){
	#Ajuste das permissões do samba
	setcfg Samba 'DC List' "$APP_DC_PRIMARY_NAME,$APP_DC_SECONDARY_NAME"
	setcfg -f /etc/config/nm.conf global 'domain_name_server_1' "$APP_DNS1"
	setcfg -f /etc/config/nm.conf global 'domain_name_server' "$APP_DNS1"
	setcfg -f /etc/config/nm.conf global 'domain_name_server_2' "$APP_DNS2"
}


function set_KerberosBaseProps() {
	local upperDOMAIN
	upperDOMAIN=$(echo "$APP_NAS_DOMAIN" | tr '[:lower:]' '[:upper:]')

	setcfg -f /etc/config/krb5.conf libdefaults default_realm "${upperDOMAIN}"

	realmList=$(echo -e "{\nkdc = ${APP_DC_PRIMARY_NAME}\nkdc = ${APP_DC_SECONDARY_NAME}\n}")
	setcfg -f /etc/config/krb5.conf realms "${upperDOMAIN}" "${realmList}"

	setcfg -f /etc/config/krb5.conf domain_realms ".${APP_DC_PRIMARY_NAME}" "${upperDOMAIN}"
	setcfg -f /etc/config/krb5.conf domain_realms ".${APP_DC_SECONDARY_NAME}" "${upperDOMAIN}"

	#todo:test: Validar se com a linha abaixo a cois melhora
	setcfg -f /etc/config/krb5.conf libdefaults dns_lookup_realm 'true'

}


function join_to_domain() {
	local -i _success="$1"
	local -i ret=1
	local -i retries
	local result
	local upperNETBIOS
	upperNETBIOS=$(echo "$APP_NAS_NETBIOS_DOMAIN" | tr '[:lower:]' '[:upper:]')

	set_DNS

	set_SambaBaseProps

	set_KerberosBaseProps

	#todo:test: Verificar a forma de ajudar o processo de inserção no domínio acima. Caso ainda falhe, tentar alterar arquivos .config\nm.conf e .\config\smb.conf

	#! para qcli_domainsecurity o argumento -m
	#!foi usado ao invés do argumento -q como no caso abaixo(remover comentario após elucidação de motivos)
	echo 'Ajustando as configurações do domínio.'
	echo 'Aguarde alguns minutos...'
	test_domain ret 1
	until [[ $ret -eq 0 ]]; do
		#! ERA ip="$APP_DNS1" ABAIXO
		# result=$(qcli_domainsecurity -q domain="$APP_NAS_DOMAIN" \
		# 	NetBIOS="$upperNETBIOS" dns_mode=manual ip="$APP_DNS1" ip="$APP_DNS2" \
		# 	domaincontroller="$APP_DC_PRIMARY_NAME" \
		# 	username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD")
		#!alert
		#todo:urgent: Preconditions below:
		# DNS = ips dos DCs. Netbios = uppercase do primeiro
		# Servidores(plural) de tempo = DCs hostnames
		# nome do domínio = fqdn lowercase
		# controladores de domínio = o par de DCs(como informar mais de um?????)
		echo "Resumo: NETBIOS = ${upperNETBIOS} domain=${APP_NAS_DOMAIN} AD_server=${APP_DC_PRIMARY_NAME}"
		result=$(qcli_domainsecurity -m domain="$APP_NAS_DOMAIN" \
			NetBIOS="$upperNETBIOS" AD_server="$APP_DC_PRIMARY_NAME" \
			username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD" description="$APP_NAS_HOSTNAME")
		ret=$?
		echo "Retorno da chamada(exit_code=$ret) de união ao domínio = $result" | slog 7
		sleep "$APP_MIN_TIME_SLICE"
		test_domain ret 1
		retries=0
		while [[ $ret -ne 0 ]]; do
			((retries++))
			echo "Tentativa($retries) de ingresso no domínio falhou."
			echo 'Informe as credenciais novamente'
			read -p 'Digite a conta ADM do Dominio:' -r APP_DOMAIN_ADM_ACCOUNT
			read -p "Digite a senha para $APP_NAS_NETBIOS_DOMAIN\\$APP_DOMAIN_ADM_ACCOUNT:" -ers APP_DOMAIN_ADM_ACCOUNT_PWD
			#Nova tentativa com as novas credenciais
			# qcli_domainsecurity -q domain="$APP_NAS_DOMAIN" \
			# 	NetBIOS="$APP_NAS_NETBIOS_DOMAIN" dns_mode=manual \
			# 	ip="$APP_DNS1" domaincontroller="$APP_DC_PRIMARY_NAME" \
			# 	username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD"
			result=$(qcli_domainsecurity -m domain="$APP_NAS_DOMAIN" \
				NetBIOS="$upperNETBIOS" AD_server="$APP_DC_PRIMARY_NAME" \
				username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD" description="$APP_NAS_HOSTNAME")
			ret=$?
			echo "Chamada repetida a qcli_domainsecurity com retorno: $ret" | slog 7
		done
		test_domain ret 1 #nova rodada
	done

	echo "Entrou no domínio corretamente" | slog 5
	echo 'aguardando sincronização DCs...'
	sleep 15
	printf -v "$1" "%d" "$ret"
}

function config_snmp() {
	local ret="$1"
	setcfg SNMP 'Service Enable' TRUE
	setcfg SNMP 'Listen Port' 161
	setcfg SNMP 'Trap Community'
	setcfg SNMP 'Event Mask 1' 7
	setcfg SNMP 'Trap Host 1' "$APP_SNMP_SERVER1"
	setcfg SNMP 'Event Mask 2' 7
	setcfg SNMP 'Trap Host 2' "$APP_SNMP_SERVER2"
	setcfg SNMP 'Event Mask 3' 7
	setcfg SNMP 'Trap Host 3' #Originalmente esta linha(meio sem sentido)
	setcfg SNMP 'Version' 3
	setcfg SNMP 'Auth Type' 0
	setcfg SNMP 'Auth Protocol' 0
	setcfg SNMP 'Priv Protocol' 0
	setcfg SNMP 'User' "$APP_MONITOR_USER"
	setcfg SNMP 'Auth Key' #todo: valores a serem coletados e ainda desconhecidos
	setcfg SNMP 'Priv Key' #todo: idem acima
	printf -v "$1" "%d" "0"
}

function set_shares_permissions() {
	local -i ret="$1"
	local -i localID="$2"

	#todo:future: Implementar sub-rotina para exibir entrada e tratar os erros das chamadas a qcli_sharedfolder

	upperNETBIOS=$(echo "$APP_NAS_NETBIOS_DOMAIN" | tr '[:lower:]' '[:upper:]')

	#todo:urgent: Setar atributos dos compartilhamentos, inclusive o do sistema para conteudo abaixo
	# qcli_sharedfolder sharename=*** -p WinACLEnabled=1 -e RecycleBinEnable=0
	echo "Ajustando habilitação da WinACL e Lixeira globalmente..."
	#todo Rever comandos abaixo, cujo eero segue: [info] -p is not defined, please check command again!!
	qcli_sharedfolder -p WinACLEnabled=1 ACLEnabled=1  #Enable advanced and ACL permissions for MS share
	qcli_sharedfolder -d
	echo "Desabilitando a lixeira para publico"
	qcli_sharedfolder -e RecycleBinEnable=0 sharename=publico
	echo "Desabilitando a lixeira para restrito"
	qcli_sharedfolder -e RecycleBinEnable=0 sharename=restrito
	echo "Desabilitando a lixeira para critico"
	qcli_sharedfolder -e RecycleBinEnable=0 sharename=critico
	echo "Desabilitando a lixeira para suporte"
	qcli_sharedfolder -e RecycleBinEnable=0 sharename=suporte
	echo "Desabilitando a lixeira para espelho"
	qcli_sharedfolder -e RecycleBinEnable=0 sharename=espelho

	echo "Ajustando permissões para o local $localID ..."

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6

	qcli_sharedfolder -B sharename=suporte domain_grouprd="$upperNETBIOS\\G_SIS_ADMINS" | slog 6

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6

	qcli_sharedfolder -B sharename=publico domain_grouprd="$upperNETBIOS\\Domain Users" | slog 6
	qcli_sharedfolder -B sharename=entrada domain_grouprw="$upperNETBIOS\\Domain Users" | slog 6

	local primaryGroup
	get_primary_group primaryGroup "$localID"

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprd="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprd="$upperNETBIOS\\$primaryGroup" | slog 6

}
