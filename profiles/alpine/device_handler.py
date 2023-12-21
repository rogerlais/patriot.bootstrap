import subprocess
import os
import sys
import importlib

# External modules
props = None
hosts = None
base_dir = None
secret_file = None
host_key = [None, None]


def get_key_value(text, key):
    lines = text.split("\n")
    for line in lines:
        parts = line.split("=")
        if len(parts) == 2:
            current_key = parts[0].strip().lower()
            value = parts[1].strip()
            if current_key == key.lower():
                return value
    return None  # Return None if the key is not found


def check_host(host):
    # remote_command = 'grep -E \"^(ID|VERSION_ID)=\" /etc/os-release'
    remote_command = (
        "source /etc/profile > nul ; "  # todo:design: Verificar possibilidade de chamar algo mais leve para recarregar o profile para sessão não intereativa
        'echo "VERSION=${PATRIOT_VERSION}"; '
        'echo "STATUS=${PATRIOT_STATUS}"; '
        "echo \"OS=$(grep -E '^ID=' /etc/os-release | cut -d= -f2)\"; "
        "echo \"OS_VER=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2)\"; "
    )
    result = False
    ret = execute_remote_command(
        host.ip, get_ssh_user(host), get_ssh_pwd(host), remote_command
    )
    if ret is not None:
        OSName = get_key_value(ret, "OS")
        if (OSName is not None) and (OSName.lower() == "alpine"):
            host.OSName = "Alpine"
            host.OSVersion = get_key_value(ret, "OS_VER")
            host.version = get_key_value(ret, "VERSION")
            host.status = int(get_key_value(ret, "STATUS"))
            if host.status < 0:
                host.status = get_status(host)
            result = host.status < 0  # Need OOB/injection
    return result


def get_status(host):
    # *Allways dotsource /etc/profile to get PATRIOT_STATUS or any other value
    remote_command = "source /etc/profile > nul; echo ${PATRIOT_STATUS}"
    ret = execute_remote_command(
        host.ip, get_ssh_user(), get_ssh_pwd(), remote_command
    ).replace("\n", "")
    # if a number, host has a status in progress
    if ret.isnumeric():
        host.status = int(ret)
    else:
        host.status = -1
    return host.status


def inject_code_host(host):
    # chama o script de instalação
    pass


def get_alpine_pwd(host):
    global props, secret_file
    if host.mac is not None:
        passwd = host.mac.replace(":", "")
        if passwd.isdigit():  #!Regra de negocio simulada para usar o MAC como senha
            return passwd
        else:
            return props.read_config_value(
                secret_file, "SSH_USER_PWD_ALTERNATIVE"
            ).strip("'\"")
    else:
        raise Exception(f"Host {host.name} has no mac address.")


def get_ssh_user(host):
    global props, secret_file
    return props.read_config_value(secret_file, "SSH_USER").strip("'\"")


def get_ssh_pwd(host):
    global props, secret_file
    value = props.read_config_value(secret_file, "SSH_USER_PWD").strip("'\"")
    # if value end with '()' then is a function , so execute it
    if value.endswith("()"):
        value = value[:-2]
        mod_dir = os.path.dirname(os.path.abspath(__file__))
        sys.path.append(mod_dir)
        try:
            current_module = importlib.import_module(__name__)
            pwd_host_function = getattr(current_module, value)
            # pwd_host_function = getattr(globals(), value)
            if pwd_host_function is None:
                raise Exception(f"Function {value} not found.")
            result = pwd_host_function(host)
            return result
        finally:
            sys.path.remove(mod_dir)
    else:
        return value



def execute_remote_command(hostname, username, password, command):
    try:
        ssh_command = f"sshpass -p {password} ssh {username}@{hostname} '{command}'"

        # Executa o comando remoto e captura a saída
        result = subprocess.run(ssh_command, shell=True, capture_output=True, text=True)

        # Verifica se a execução foi bem-sucedida
        if result.returncode == 0:
            return result.stdout
        else:
            print(
                f"Erro ao executar o comando remoto: ({result.returncode}) \n {result.stderr}"
            )
            return None
    except Exception as e:
        print(f"Erro ao conectar ao host remoto: {str(e)}")
        return None


def load_module():
    global base_dir
    base_dir = os.path.dirname(os.path.abspath(__file__))
    global secret_file
    secret_file = os.path.join(base_dir, ".secret")
    opt_path = os.path.abspath(os.path.join(base_dir, "../../opt"))
    sys.path.append(opt_path)
    try:
        try:
            global hosts
            hosts = importlib.import_module("hosts")
        except ImportError as e:
            print(f"Error importing module hosts : {str(e)}")
        try:
            global props
            props = importlib.import_module("props")
        except ImportError as e:
            print(f"Error importing module props : {str(e)}")
    finally:
        sys.path.remove(opt_path)


def main():
    load_module()
    fpath = os.path.join(base_dir, ".secret")  # todo:design alternate based config
    username = props.read_config_value(fpath, "SSH_USER")
    pwd = props.read_config_value(fpath, "SSH_USER_PWD")
    hostname = "192.168.1.127"
    remote_command = 'grep -E "^(ID|VERSION_ID)=" /etc/os-release'
    result = execute_remote_command(hostname, username, pwd, remote_command)
    print(result)


if __name__ == "__main__":
    main()
else:
    load_module()
