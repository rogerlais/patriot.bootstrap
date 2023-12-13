import os
import sys
import paramiko
import subprocess
import socket
from scapy.all import ICMP, IP
from hosts import HostInfo, show_hosts
from patriot_config import Config
from ping3 import ping, verbose_ping

script_dir = os.path.dirname(os.path.abspath(__file__))
lib_path = os.path.join(script_dir, 'opt')
sys.path.append(lib_path)
from hosts import HostInfo, show_hosts


def test_icmp(ip_address, count=4):
    try:
        return  ping(ip_address)
    except Exception as e:
        #print(f"Error: {e}")
        return False

def check_icmp(ip):
    try:
        #icmp = IP(dst=ip)/ICMP()
        #resp = str(icmp, timeout=1, verbose=0)        
        #return resp is not None
        return test_icmp(ip, 3)

    except Exception as e:
        return False

def check_ssh(ip):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)

        return sock.connect_ex((ip, 22)) == 0 

    except Exception as e:
        return False

def scan_host(ip, ssh_hosts):
    
    #host = HostInfo(name=socket.gethostbyaddr(ip)[0], ip=ip, mac=mac_address)
    #if passed ip is a name, get ip address
    try:
        name = ip
        hip = ip
        socket.inet_aton(ip)
    except ( socket.error, OSError ) as e:
        try:
            hip = socket.gethostbyname(ip)
        except ( socket.gaierror, OSError ) as ein:
            #print(f"Não foi possível resolver o nome {ip}")
            return
    host = HostInfo(name=name, ip=hip, mac="" )

    if check_icmp(ip):
        host.icmp = True
    else:
        host.icmp = False

    #take ssh status and mac address
    if check_ssh(ip):
        #print(f"Porta SSH (22) está aberta em {ip}")
        host.ssh = True
    else:
        #print(f"Porta SSH (22) está fechada em {ip}")
        host.ssh = False

    try:
        arp_result = subprocess.check_output(['arp', '-n', ip])
        host.mac = arp_result.split()[8].decode('utf-8')
    except ( subprocess.CalledProcessError, IndexError ) as e:
        host.mac = "N/A"

    #register host at hosts list
    ssh_hosts.append(host)


def scan( config ):
    #scan hosts
    ssh_hosts = []

    if config.env == 'dev' and config.dbg_flag:
        cmd = "nmap -p 22 --open -Pn -PE -PS22 192.168.1.120-130 | grep 'Nmap scan' | cut -d' ' -f5"
    else:
        if config.control.live_only:
            cmd="nmap -p 22 --open -Pn -PE -PS22 {config.control.subnet_cidr} | grep 'Nmap scan' | cut -d' ' -f5"
            #entries = subprocess.getoutput(f"nmap -p 22 --open -Pn -PE -PS22 {config.control.subnet_cidr} | grep 'Nmap scan' | cut -d' ' -f5").split()
        else:
            cmd="nmap -p 22 -Pn -PE -PS22 {config.control.subnet_cidr} | grep 'Nmap scan' | cut -d' ' -f5"
            #entries = subprocess.getoutput(f"nmap -p 22 -Pn -PE -PS22 {config.control.subnet_cidr} | grep 'Nmap scan' | cut -d' ' -f5").split()

    entries = subprocess.getoutput(cmd).split()
    for ip in entries:
        scan_host(ip, ssh_hosts)

    #filter hosts
    if config.control.live_only:
        ssh_hosts = [ host for host in ssh_hosts if ( host.icmp or host.ssh ) ]

    return ssh_hosts

def main():
    ip_range = "192.168.1.1/24"
    ssh_hosts = []
    #entries = subprocess.getoutput(f"nmap -p 22 --open {ip_range} | grep 'Nmap scan' | cut -d' ' -f5").split():
    #entries = subprocess.getoutput(f"nmap -T4 -A -v -p 1,22,161-162 {ip_range} | grep 'Nmap scan' | cut -d' ' -f5").split():
    #entries = subprocess.getoutput(f"nmap -T4 -A -v -p 1,22,161-162 {ip_range} | grep 'Nmap scan' | cut -d' ' -f5").split()
    #entries = subprocess.getoutput(f"nmap -T4 -A -v -p 1,22 {ip_range} | grep 'Nmap scan' | cut -d' ' -f5").split()
    entries = subprocess.getoutput(f"nmap -p 22 --open -Pn -PE -PS22 {ip_range} | grep 'Nmap scan' | cut -d' ' -f5").split()
    for ip in entries:
        scan_host(ip, ssh_hosts)
    print("\nHosts que respondem ao SSH:")
    show_hosts( ssh_hosts )

if __name__ == "__main__":
    main()
