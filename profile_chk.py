#from hosts import HostInfo
import os
import sys
import imp
#import importlib

#load initial configuration and libs
script_dir = os.path.dirname(os.path.abspath(__file__))
lib_path = os.path.join(script_dir, 'opt')
sys.path.append(lib_path)
from scan_host_mac import scan
from hosts import HostInfo, show_hosts


def get_profile_check(profile_name, item, path_modulos):
    # Formata o nome do módulo com base no nome do item
    mod_name = profile_name + "/profile"

    try:
        # Constrói o caminho completo para o módulo
        full_path = os.path.join(path_modulos, f"{mod_name}.py")

        # Importa dinamicamente o módulo usando imp.load_source
        modulo = imp.load_source(mod_name, full_path)

        # Obtém a função "check_host" do módulo e a chama
        if hasattr(modulo, "check_host") and callable(getattr(modulo, "check_host")):
            resultado = modulo.check_host(item)
            return resultado
        else:
            return f"Módulo {mod_name} não possui uma função 'check_host' válida."
    except Exception as e:
        return f"Erro ao importar o módulo {full_path}: {str(e)}"


#####----------------------------
# Exemplo de uso
#items = [Item("module1"), Item("module2"), Item("module3")]
#for item in items:
#    resultado = get_profile_check('nome', item)
#    print(resultado)

def main():
    #take current path and append /profiles/
    script_dir = os.path.dirname(os.path.abspath(__file__))
    profile_path = os.path.join(script_dir, 'profiles')
    test=HostInfo(name="teste", ip="teste", mac="HostInfo")
    test_col = [ test , HostInfo(name="nomegrande-teste2", ip="teste2", mac="HostInfo2"), HostInfo(name="teste2", ip="teste2", mac="HostInfo2")]
    for item in test_col:
        resultado = get_profile_check( "alpine" , item, profile_path)
        print(resultado)

#!testes
if __name__ == "__main__":
    main()