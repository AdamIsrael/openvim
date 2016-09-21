
##
# A simple wrapper around HTTP to aid the maiking of REST clients
import requests

class RESTClient:
    def __init__(self):
        pass
    def get(self, uri):
        return requests.get(uri)

    def post(self, uri, data, headers={}):
        return requests.post(uri, data=data, headers=headers)

    def delete(self, uri):
        return requests.delete(uri)
