import json

class Config:
    def __init__(self, data):
        #self.control = data.get('control')
        self.control = self.ControlConfig(data.get('control', {}))
        self.scan = data.get('scan')
        self.profiles = [self.ProfileConfig(profile) for profile in data.get('profiles', [])]

    class ControlConfig:
        def __init__(self, control_data):
            self.port = control_data.get('port')
            self.conn_timeout = control_data.get('conn_timeout')
            self.read_timeout = control_data.get('read_timeout')
            self.subnet_cidr = control_data.get('subnet_cidr')            
            self.live_only = control_data.get('live_only')
            self.verbosity = control_data.get('verbosity')


    class ProfileConfig:
        def __init__(self, profile_data):
            self.name = profile_data.get('name')
            self.rule_name = profile_data.get('rule_name')


# Carrega os dados do arquivo JSON
def load_config(file_path='config.json'):
    with open(file_path, 'r') as file:
        data = json.load(file)
    return Config(data)
