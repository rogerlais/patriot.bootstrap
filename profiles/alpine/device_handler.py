import subprocess
import os
import sys
import importlib
import paramiko

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
    ret, err = execute_remote_command(
        host.ip, get_ssh_user(host), get_ssh_pwd(host), remote_command
    )
    if ret is not None:
        OSName = get_key_value(ret, "OS")
        if (OSName is not None) and (OSName.lower() == "alpine"):
            host.OSName = "Alpine"
            host.OSVersion = get_key_value(ret, "OS_VER")
            host.version = get_key_value(ret, "VERSION")
            try:
                host.status = int(get_key_value(ret, "STATUS"))
            except:
                host.status = -1
            if host.status < 0:  # Try again
                host.status = get_status(host)
            result = host.status < 0  # Need OOB/injection
    return result


def get_status(host):
    # *Allways dotsource /etc/profile to get PATRIOT_STATUS or any other value
    remote_command = "source /etc/profile > nul; echo ${PATRIOT_STATUS}"
    ret, err = execute_remote_command(
        host.ip, get_ssh_user(host), get_ssh_pwd(host), remote_command
    )
    ret = ret.replace("\n", "")
    # if a number, host has a status in progress
    if ret.isnumeric():
        host.status = int(ret)
    else:
        host.status = -1
    return host.status


def copy_folder(sftp, local_dir, remote_dir):
    local_dir = os.path.abspath(local_dir)
    try:
        sftp.stat(remote_dir)
    except IOError:
        sftp.mkdir(remote_dir)  #todo:test: verify tooo long path inexistent immpact
    for item in os.listdir(local_dir):
        if os.path.isfile(os.path.join(local_dir, item)):
            sftp.put(os.path.join(local_dir, item), os.path.join(remote_dir, item))
        else:
            try:
                new_dir=os.path.join(remote_dir, item)
                try:
                    sftp.stat(new_dir)
                except IOError:
                    sftp.mkdir(new_dir)
            except Exception as e:
                ret = f"Erro criando diretório {os.path.join(remote_dir, item)}: {e}"
                return 1, ret
            copy_folder(
                sftp, os.path.join(local_dir, item), os.path.join(remote_dir, item)
            )
    return 0, None


def inject_code_host(host):
    # chama o script de instalação
    # Create a ssh connection to copy files to remote host
    output = None
    error = None
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(host.ip, username=get_ssh_user(host), password=get_ssh_pwd(host))

        # Copy files to remote host
        sftp = ssh.open_sftp()
        remote_path = "/tmp/patriot"
        try:
            try:
                sftp.stat(remote_path)
            except IOError:
                sftp.mkdir(remote_path)
            src = os.path.join(base_dir, "install.sh")
            dst = os.path.join(remote_path, "install.sh")
            sftp.put(src, dst)
            src = os.path.join(base_dir, ".env")
            dst = os.path.join(remote_path, ".env")
            sftp.put(src, dst)
            src = os.path.join(base_dir, ".secret")
            dst = os.path.join(remote_path, ".secret")
            sftp.put(src, dst)
            # lib files at two levels up
            src = os.path.join(base_dir, "lib/")
            dst = os.path.join(remote_path, "lib/")
            ret, error = copy_folder(sftp, src, dst)
            if ret != 0:
                return None, error
        except Exception as e:
            error = f"Error copying files to remote host: {e}"
            output = None
            return output, error
        finally:
            sftp.close()

        # Execute the script
        remote_command = "chmod +x /tmp/patriot/install.sh; ash /tmp/patriot/install.sh"
        stdin, stdout, stderr = ssh.exec_command(remote_command)
        output = stdout.read().decode("utf-8")
        error = stderr.read().decode("utf-8")
        print(f"Saida do comando: {output}")
        print(f"Erro do comando: {error}")
    finally:
        if ssh.get_transport().is_active():
            ssh.close()
    return output, error


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
    ssh = paramiko.SSHClient()

    # O método set_missing_host_key_policy() decide o que fazer se o servidor ao qual você está se conectando não estiver no known_hosts
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        # Tente estabelecer uma conexão
        try:
            ssh.connect(hostname, username=username, password=password)
        except paramiko.AuthenticationException:
            print("Falha na autenticação.")
            return None, "Falha na autenticação."
        except paramiko.SSHException as e:
            print(f"Erro na conexão: {e}")
            print("Atualizando a chave SSH local...")
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            try:
                ssh.connect(hostname, username=username, password=password)
            except Exception as e:
                return None, f"Erro na conexão. {e}"
        except Exception as e:
            return None, f"Erro na conexão. {e}"

        # Execute o comando
        stdin, stdout, stderr = ssh.exec_command(command)

        # Capture a saída do comando
        output = stdout.read().decode("utf-8")
        error = stderr.read().decode("utf-8")
    finally:
        if ssh.get_transport() and ssh.get_transport().is_active():
            ssh.close()
    return output, error


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
    result, err = execute_remote_command(hostname, username, pwd, remote_command)
    print(result)


if __name__ == "__main__":
    main()
else:
    load_module()
