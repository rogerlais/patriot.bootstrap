#from hosts import HostInfo
import os
import sys
import importlib

config = None

#load initial configuration and libs
script_dir = os.path.dirname(os.path.abspath(__file__))
lib_path = os.path.join(script_dir, 'opt')
sys.path.append(lib_path)
from scan_host_mac import scan
from hosts import HostInfo, show_hosts
from patriot_config import Config

def inject_profile_script( profile_name, host, config ):
    #todo:design reagrupar elementos em comum para a carga de módulos
    # Formata o nome do módulo com base no nome do item
    mod_name = profile_name + "/device_handler"

    try:
        # Constrói o caminho completo para o módulo
        full_path = os.path.join(config.profiles_dir, f"{mod_name}.py")

        # Importa dinamicamente o módulo usando imp.load_source
        #module = imp.load_source(mod_name, full_path)
        #add parent dir to path
        sys.path.append( os.path.abspath(os.path.join(full_path, os.pardir)) )
        try:
            #!IMPORTANTE = O nome do módulo pode ter conflito com outro do sistema - assim, fomos originais(device_handler)
            module = importlib.import_module('device_handler')
        finally:
            sys.path.remove( os.path.abspath(os.path.join(full_path, os.pardir)) )
        # Obtém a função "check_host" do módulo e a chama
        #if hasattr(module, "check_host") and callable(getattr(module, "check_host")):
        if hasattr(module, "inject_code_host"):
            inject_code_host_function = getattr(module, 'inject_code_host')
            result = inject_code_host_function( host )
            return result
        else:
            return f"Módulo {full_path} não possui uma função 'check_host' válida."
    except Exception as e:
        return f"Erro ao importar o módulo {full_path}: {str(e)}"

def get_profile_check(profile_name, item, config):
    #todo:design remover o lixo
    # Formata o nome do módulo com base no nome do item
    mod_name = profile_name + "/profile"

    try:
        # Constrói o caminho completo para o módulo
        full_path = os.path.join(config.profiles_dir, f"{mod_name}.py")

        # Importa dinamicamente o módulo usando imp.load_source
        #module = imp.load_source(mod_name, full_path)
        #add parent dir to path
        sys.path.append( os.path.abspath(os.path.join(full_path, os.pardir)) )
        try:
            #!IMPORTANTE = O nome do módulo pode ter conflito com outro do sistema - assim, fomos originais(device_handler)
            module = importlib.import_module('device_handler')
        finally:
            sys.path.remove( os.path.abspath(os.path.join(full_path, os.pardir)) )
        # Obtém a função "check_host" do módulo e a chama
        #if hasattr(module, "check_host") and callable(getattr(module, "check_host")):
        if hasattr(module, "check_host"):
            check_host_function = getattr(module, 'check_host')
            result = check_host_function( item )
            return result
        else:
            return f"Módulo {full_path} não possui uma função 'check_host' válida."
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