import subprocess
import os
import sys
import importlib

#External modules
props = None
hosts = None
base_dir = None
secret_file = None

def check_host( host ):
    remote_command = 'grep -E \"^(ID|VERSION_ID)=\" /etc/os-release'
    ret = execute_remote_command(host.ip, get_ssh_user(), get_ssh_pwd(), remote_command)
    #if some line of ret has ID=alpine, tehen is True
    if any("ID=alpine" in s for s in ret.splitlines()):
        host.OSName = "Alpine"
        status = get_status( host )
        return ( status < 0 )
    else:
        return False


def get_status( host ):
    remote_command = 'source /etc/profile > nul; echo ${PATRIOT_STATUS}'
    ret = execute_remote_command(host.ip, get_ssh_user(), get_ssh_pwd(), remote_command).replace('\n', '')
    #if a number, host has a status in progress
    if ret.isnumeric():
        host.status = int( ret )
    else:
        host.status = -1
    return host.status

def inject_code_host( host ):
    #chama o script de instalação
    pass    

def get_ssh_user():
    global props, secret_file
    return props.read_config_value(secret_file, 'SSH_USER')

def get_ssh_pwd():
    global props, secret_file
    return props.read_config_value(secret_file, 'SSH_USER_PWD')


def execute_remote_command(hostname, username, password, command):
    try:
        ssh_command = f"sshpass -p {password} ssh {username}@{hostname} '{command}'"

        # Executa o comando remoto e captura a saída
        result = subprocess.run(ssh_command, shell=True, capture_output=True, text=True)

        # Verifica se a execução foi bem-sucedida
        if result.returncode == 0:
            return result.stdout
        else:
            return f"Erro ao executar o comando remoto: {result.stderr}"
    except Exception as e:
        return f"Erro ao conectar ao host remoto: {str(e)}"


def load_module():
    global base_dir
    base_dir = os.path.dirname(os.path.abspath(__file__))
    global secret_file
    secret_file = os.path.join(base_dir, '.secret' )
    opt_path = os.path.abspath(os.path.join(base_dir, "../../opt"))
    sys.path.append( opt_path )
    try:
        try:
            global hosts
            hosts = importlib.import_module("hosts")
        except ImportError as e:
            print(f"Error importing module hosts : {str(e)}")
        try:
            global props 
            props = importlib.import_module( 'props' )
        except ImportError as e:
            print(f"Error importing module props : {str(e)}")
    finally:
        sys.path.remove( opt_path )


def main():
    load_module()
    fpath=os.path.join(base_dir, '.secret' )  #todo:design alternate based config
    username = props.read_config_value(fpath, 'SSH_USER')
    pwd = props.read_config_value(fpath, 'SSH_USER_PWD')
    hostname = '192.168.1.127'
    remote_command = 'grep -E \"^(ID|VERSION_ID)=\" /etc/os-release'
    result = execute_remote_command(hostname, username, pwd, remote_command)
    print(result)


if __name__ == "__main__":
    main()
else:
    load_module()
