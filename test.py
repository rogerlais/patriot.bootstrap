import paramiko

# Substitua 'hostname', 'username' e 'password' pelos seus valores
hostname = "192.168.1.134"
username = "aluno"
password = "ifpb"

# Crie uma nova instância do cliente SSH
ssh = paramiko.SSHClient()

# O método set_missing_host_key_policy() decide o que fazer se o servidor ao qual você está se conectando não estiver no known_hosts
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    # Tente estabelecer uma conexão
    try:
        ssh.connect(hostname, username=username, password=password)
        print("Conexão estabelecida com sucesso.")
    except paramiko.AuthenticationException:
        print("Falha na autenticação.")
    except paramiko.SSHException as e:
        print(f"Erro na conexão: {e}")
        print("Atualizando a chave SSH local...")
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(hostname, username=username, password=password)

    # Execute o comando
    stdin, stdout, stderr = ssh.exec_command('source /etc/profile > nul; printenv')

    # Capture a saída do comando
    output = stdout.read().decode('utf-8')
    print(f"Saida do comando: {output}")


finally:
    if ssh.get_transport().is_active():
        print("Fechando a conexão.")
        ssh.close()
