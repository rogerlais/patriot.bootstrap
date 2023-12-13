import sys
import os
import subprocess
import socket
from  patriot_config import load_config
import json


#load initial configuration and libs
script_dir = os.path.dirname(os.path.abspath(__file__))
lib_path = os.path.join(script_dir, 'opt')
sys.path.append(lib_path)
from scan_host_mac import scan
from hosts import HostInfo, show_hosts




def process_hosts( config, hosts ):
    for host in hosts:
        for profile in config.profiles:
            to_proceed, bootstrap_proc = get_profile_check( profile , host )
            if to_proceed:
                bootstrap_proc( host )
                break
        


def run_scanner( config ):
    hosts = scan( config.control.subnet_cidr , config.control.live_only )
    return hosts

def main():
    #load initial configuration
    config = load_config()

    try:
        if config.control.conn_timeout == 0:
            config.control.conn_timeout =  int(input("Digite o tempo limite para conexões d retorno: "))
    except ValueError:
        print("Digite um número inteiro.")
        sys.exit(1)

    try:
        if config.control.subnet_cidr == '':
            config.control.subnet_cidr =  int(input("Digite a rede de pesquisa local(cidr): "))
    except ValueError:
        print("Erro lendo valor da rede.")
        sys.exit(1)

    while True:
        # Run the scanner
        hosts = run_scanner( config )
        if config.control.verbosity > 3:
            print( "Hosts encontrados e relevantes:")
            show_hosts(hosts)
        
        # Run the rules
        process_hosts( config , hosts )

        # Run the control manager
    pass

if __name__ == "__main__":
    main()
