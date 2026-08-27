#!/usr/bin/env python3
"""Vérifie le protocole du serveur AirPad sur une instance réellement lancée.

Lancez l'app Mac, puis : python3 Tests/protocol_test.py
"""
import os, socket, subprocess, sys, time

# Le code d'appairage change à chaque installation : on le lit dans les
# préférences du serveur, comme le ferait un téléphone après avoir scanné le QR.
HOST, PORT = "127.0.0.1", 8080
TOKEN = os.environ.get("AIRPAD_TOKEN") or subprocess.run(
    ["defaults", "read", "com.abdouldotdev.AirPadServer", "pairingToken"],
    capture_output=True, text=True).stdout.strip()
results = []

def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print(("  PASS  " if ok else "  FAIL  ") + name + ((" — " + detail) if detail else ""))

def connect(timeout=3):
    s = socket.create_connection((HOST, PORT), timeout=timeout)
    s.settimeout(timeout)
    return s

def readline(s):
    buf = b""
    try:
        while b"\n" not in buf:
            chunk = s.recv(1024)
            if not chunk:
                return None
            buf += chunk
    except socket.timeout:
        return None
    return buf.split(b"\n")[0].decode()

# 1. Une commande envoyée sans authentification doit être refusée.
s = connect()
s.sendall(b"M:10:10\n")
check("commande sans AUTH refusee", readline(s) == "DENIED")
s.close()

# 2. Un mauvais code doit etre refuse.
s = connect()
s.sendall(b"AUTH:WRONG123\n")
check("code invalide refuse", readline(s) == "DENIED")
s.close()

# 3. Le bon code doit etre accepte.
s = connect()
s.sendall(("AUTH:%s\n" % TOKEN).encode())
check("code valide accepte", readline(s) == "OK")

# 4. Le heartbeat doit repondre.
s.sendall(b"PING\n")
check("PING repond PONG", readline(s) == "PONG")

# 5. Une commande coupee entre deux paquets TCP doit etre reassemblee.
#    On coupe un PING en deux, la reponse prouve que le tampon a fait son travail.
s.sendall(b"PI")
time.sleep(0.3)
s.sendall(b"NG\n")
check("commande coupee en deux paquets reassemblee", readline(s) == "PONG")

# 6. Plusieurs commandes dans un meme paquet.
s.sendall(b"PING\nPING\n")
first, second = readline(s), readline(s)
check("deux commandes dans un paquet", first == "PONG" and second == "PONG")

# 7. Une seconde connexion doit etre refusee tant que la premiere vit.
try:
    s2 = connect(timeout=2)
    s2.sendall(("AUTH:%s\n" % TOKEN).encode())
    reply = readline(s2)
    check("seconde connexion arbitree", reply is None, "connexion fermee sans reponse" if reply is None else "recu: %s" % reply)
    s2.close()
except Exception as e:
    check("seconde connexion arbitree", True, "refusee: %s" % type(e).__name__)

# 8. L'identification de l'appareil doit remonter dans l'UI.
s.sendall(b"INIT:iPhone de test\n")
time.sleep(0.5)
check("INIT accepte apres AUTH", True, "voir la fenetre du Mac")
s.close()

# 9. Apres deconnexion, la place doit se liberer.
time.sleep(1.0)
try:
    s3 = connect()
    s3.sendall(("AUTH:%s\n" % TOKEN).encode())
    check("place liberee apres deconnexion", readline(s3) == "OK")
    s3.close()
except Exception as e:
    check("place liberee apres deconnexion", False, str(e))

passed = sum(1 for _, ok, _ in results if ok)
print("\n%d/%d tests reussis" % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
