import os
import sys

# Get the directory of the main script
main_script_directory = os.path.dirname(os.path.abspath(__file__))
module_path = os.path.abspath(os.path.join(main_script_directory, "../opt/hosts/hosts.py"))
sys.path.append(os.path.dirname(module_path))
try:
    import hosts
except ImportError:
    print(f"Error importing module {module_path}")
finally:
    sys.path.remove(os.path.dirname(module_path))



#from ../../opt/hosts import HostInfo

def check_host( host ):
    return True
