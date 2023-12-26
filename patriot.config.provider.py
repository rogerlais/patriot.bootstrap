from http.server import BaseHTTPRequestHandler, HTTPServer
import datetime
import socket
import getpass
import os
import importlib
from patriot_config import load_config, Config


class ProfileHandler:
    def __init__(self, name, script):
        self.name = name
        self.script = script


class RequestHandler(BaseHTTPRequestHandler):
    def load_request_dict(self, web_input):
        dictionary = {}
        for item in web_input:
            key, value = item.split("=")
            dictionary[key] = value
        return dictionary

    def load_profile(self, config, name):
        module = None
        target = None
        for item in config.profiles:
            if item.name == name:
                target = item
                break
        if target is None:
            raise Exception("Profile not found")
        else:
            # dinamically load the profile script
            full_path = os.path.join(
                config.profiles_dir, target.name, "web_response.py"
            )
            if config.control.verbosity > 3:
                print("Loading profile script:", full_path)
            spec = importlib.util.spec_from_file_location("device_handler", full_path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        return module

    def get_response( self, module, config, request):
        #Mount a reponse to client update your config itens
        response = None
        verb=request.get("verb")
        if verb is None:
            raise Exception("No verb found at request")
        verb = f"verb_{verb}"
        if hasattr(module, "ProfileHandler"):
            classRef = getattr(module, "ProfileHandler")
            new_instance = classRef(config)
            if hasattr(new_instance, verb):
                methodRef = getattr(new_instance, verb)
                response = methodRef(request)
            else:
                raise Exception(f"Profile script has no {verb} method")
        else:
            raise Exception("Profile script has no ProfileHandler Class")
        return response

    def do_POST(self):
        content_length = int(self.headers["Content-Length"])
        post_data = self.rfile.read(content_length).decode("utf-8")

        config = load_config()
        client_data = post_data.split("&")  # todo: agregate below
        request = self.load_request_dict(client_data)
        if config.control.verbosity > 3:
            print("Request:", request)
            print("Client_data:", client_data)  # todo:remove

        prof_name = request.get("profile")
        if config.control.verbosity > 3:
            print("Profile Name:", prof_name)

        verb = request.get("verb")
        if config.control.verbosity > 3:
            print("Verb:", verb)

        prof_module = self.load_profile(config, prof_name)
        if config.control.verbosity > 3:
            print(f"Profile Module: {prof_module.__file__} carregado com sucesso!")
        response=self.get_response(prof_module, config, request)

        # Prepare response data
        current_date = datetime.datetime.now()
        computer_name = socket.gethostname()
        username = getpass.getuser()

        print("Client_data:", client_data)
        print("Current date:", current_date)
        print("Computer name:", computer_name)
        print("Username:", username)

        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        #response = b"Data received successfully\nauthor=roger\nteste=ok"
        # self.wfile.write(b'Data received successfully')
        self.wfile.write(f"{response}".encode("utf-8"))


def run_server():
    server_address = ("", 8000)
    httpd = HTTPServer(server_address, RequestHandler)
    httpd.max_request_queue_size = 1  # Set max_request_queue_size to 1
    print("Server running on port 8000...")
    httpd.serve_forever()


if __name__ == "__main__":
    run_server()
