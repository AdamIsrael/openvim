
##
# A simple wrapper around HTTP to aid the maiking of REST clients
import requests

class RESTClient:
    def __init__(self):
        pass
    def get(self, uri):
        return requests.get(uri)

    def post(self, uri, data):
        return requests.post(uri, data=data)
