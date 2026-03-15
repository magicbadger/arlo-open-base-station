import socket
import json

from arlo.messages import Message

_INCOMING_KEY_MAP = {
    'messagetype':        'Type',
    'id':                 'ID',
    'systemserialnumber': 'SystemSerialNumber',
    'systemmodelnum':     'SystemModelNumber',
    'alerttype':          'AlertType',
    'batterylevel':       'BatPercent',
    'response':           'Response',
    'pirmotion':          'PIRMotion',
}
_OUTGOING_KEY_MAP = {v: k for k, v in _INCOMING_KEY_MAP.items()}

class ArloSocket:

    def __init__(self, sock=None):
        if sock is None:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        else:
            self.sock = sock
        self.sock.settimeout(30.0)

    def connect(self, host, port):
        self.sock.connect((host, port))

    def send(self, message, lowercase=False):
        if lowercase:
            data = {_OUTGOING_KEY_MAP.get(k, k): v for k, v in message.dictionary.items()}
            msg = Message(data)
        else:
            msg = message
        self.sock.sendall(msg.toNetworkMessage())

    def receive(self):
        data = self.sock.recv(1024).decode(encoding="utf-8")
        if data.startswith("L:"):
            delimiter = data.index(" ")
            dataLength = int(data[2:delimiter])
            json_data = data[delimiter+1:delimiter+1+dataLength]
        else:
            return None
        read = len(json_data)
        while read < dataLength:
            to_read = min(dataLength - read, 1024)
            chunk = self.sock.recv(to_read)
            if chunk == b'':
                raise RuntimeError("socket connection broken")
            chunk_str = chunk.decode(encoding="utf-8")
            json_data += chunk_str
            read = read + len(chunk_str)
        data = json.loads(json_data)
        if 'messagetype' in data:
            data = {_INCOMING_KEY_MAP.get(k, k): v for k, v in data.items()}
        return Message(data)

    def close(self):
        self.sock.close()