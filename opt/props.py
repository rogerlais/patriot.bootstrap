

def read_config_value(file_path, key):
    try:
        with open(file_path, 'r') as file:
            for line in file:
                if line.startswith('#'):
                    continue
                parts = line.strip().split('=')
                if len(parts) != 2:
                    continue
                if parts[0] == key:
                    return parts[1]
        return None
    except FileNotFoundError:
        return f"Arquivo não encontrado: {file_path}"
    except Exception as e:
        return f"Erro ao ler o arquivo: {str(e)}"

