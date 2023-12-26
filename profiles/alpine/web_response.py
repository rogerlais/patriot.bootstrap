from typing import Any
from patriot_config import load_config, Config


class ProfileHandler:
    def __init__(self, config ):
        self.config = config

    def verb_get_ip(self, request):
        #Dont change at moment
        if request.get("client_id") is None:
            raise Exception("No client_id found at request")
        if request.get("ip") is None:
            raise Exception("No IP found at request")
        else:
            return request.get("ip")
    
    def verb_get_dns(self, request):
        # Returna an array of dns servers to override /etc/resolv.conf(Alpine)
        response = [ '1.1.1.1', '8.8.8.8' ]
        response = f"dns={ str( response ) }"
        return response
