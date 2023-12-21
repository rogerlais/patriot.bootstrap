import os
import json


global_config = None


def transform_path(input_path):
    # Step 1: Evaluate and substitute environment variables
    expanded_path = os.path.expandvars(input_path)
    # Step 2: Convert the path to an absolute path
    absolute_path = os.path.abspath(expanded_path)
    return absolute_path


class Config:
    def __init__(self, data):
        self.env = data.get("env")
        if self.env == "dev":
            self.control = self.ControlConfig(data.get("dev", {}).get("control", {}))
            proflist = data.get("dev", {}).get("profiles", [])
        else:
            self.control = self.ControlConfig(data.get("control", {}))
            proflist = data.get("profiles", [])
        self.scan = data.get("scan")
        self.profiles = [
            self.ProfileConfig(profile) for profile in proflist
        ]
        self.dbg_flag = data.get("dbg_flag")
        self._profiles_dir = data.get("profiles_dir")

    @property
    def profiles_dir(self):
        # resolve relative path strings
        return transform_path(self._profiles_dir)

    class ControlConfig:
        def __init__(self, control_data):
            self.port = control_data.get("port")
            self.conn_timeout = control_data.get("conn_timeout")
            self.read_timeout = control_data.get("read_timeout")
            self.subnet_cidr = control_data.get("subnet_cidr")
            self.live_only = control_data.get("live_only")
            self.verbosity = control_data.get("verbosity")

    class ProfileConfig:
        def __init__(self, profile_data):
            self.name = profile_data.get("name")
            self.rule_name = profile_data.get("rule_name")


# Carrega os dados do arquivo JSON
def load_config(file_path="config.json"):
    global global_config
    if global_config is None:
        with open(file_path, "r") as file:
            data = json.load(file)
        global_config = Config(data)
    return global_config


def get_config():
    global global_config
    if global_config is None:
        load_config()
    return global_config
