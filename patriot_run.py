import sys
import os
import subprocess
import socket
from patriot_config import load_config, Config
import json
from process_profile import get_profile_check, inject_profile_script


# load initial configuration and libs
script_dir = os.path.dirname(os.path.abspath(__file__))
lib_path = os.path.join(script_dir, "opt")
sys.path.append(lib_path)  # * path global to aditional solution packages
from scan_host_mac import scan
from hosts import HostInfo, show_hosts


def process_hosts(config, hosts):
    for host in hosts:
        for profile in config.profiles:
            to_proceed = get_profile_check(config, profile.name, host)
            if to_proceed:
                print(f"Host {host.name} é relevante para o perfil {profile.name}")
                inject_profile_script(profile.name, host, config)
                break  # * Stop to first match


def run_scanner(config):
    hosts = scan(config)
    return hosts


def main():
    # load initial configuration
    # Identifica o diretório do script
    os.environ["PATRIOT_HOME"] = os.path.dirname(os.path.abspath(__file__))
    config = load_config()

    try:
        if config.control.conn_timeout == 0:
            config.control.conn_timeout = int(
                input("Digite o tempo limite para conexões d retorno: ")
            )
    except ValueError:
        print("Digite um número inteiro.")
        sys.exit(1)

    try:
        if config.control.subnet_cidr == "":
            config.control.subnet_cidr = int(
                input("Digite a rede de pesquisa local(cidr): ")
            )
    except ValueError:
        print("Erro lendo valor da rede.")
        sys.exit(1)

    while True:
        # Run the scanner
        hosts = run_scanner(config)
        if config.control.verbosity > 3:
            print(f"Hosts encontrados e relevantes: {len(hosts)}")
            show_hosts(hosts)

        # Run the rules
        process_hosts(config, hosts)

        # Run the control manager
    pass


if __name__ == "__main__":
    main()
