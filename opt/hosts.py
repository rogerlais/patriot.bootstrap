import sys

class HostInfo:
    def __init__(self, name, ip, mac):
        self.name = name
        self.ip = ip
        self.mac = mac
        self.icmp = False
        self.ssh = False
        self.OSName = ""
        self.status = -1


def format_line(instance, lens, order_attr):
    # Monta a string formatada na ordem desejada
    linha_formatada = "|".join(f"{getattr(instance, attr):<{lens}}" for attr in order_attr)

    return linha_formatada
def print_table(data):
    # Obtém os atributos da classe
    attributes = [
    r"Nome             ",
    r"Endereço IP     ",
    r"Endereço MAC    ",
    r"ICMP ativo      ",
    r"SSH ativo       ",
    r"Sistema       ",
]
    # Imprime o cabeçalho
    header = " | ".join(attributes)
    print(header)
    print("-" * len(header))

    # Imprime os dados
    instance = data[0]
    fixed_len = 18
    order_attr = ["name", "ip", "mac", "icmp", "ssh", "OSName"]
    for item in data:
        line = format_line(item, fixed_len, order_attr)
        print( line )

def show_hosts( hosts ):
    print_table(hosts)



#!testes
#test=HostInfo(name="teste", ip="teste", mac="HostInfo")
#test_col = [ test , HostInfo(name="nomegrande-teste2", ip="teste2", mac="HostInfo2"), HostInfo(name="teste2", ip="teste2", mac="HostInfo2")]
#show_hosts(test_col)