import sys
import socket
import threading
import time

data = ''

def handle_connection(client_socket):
    global data
    #testa se ainda há dados para seerem lidos
    while True:
        try:
            request_data = client_socket.recv(1024).decode("utf-8")
            if not request_data:
                break
            data = data + request_data
            #print(f"Conteúdo da requisição:\n{request_data}")
        except:
            break

def start_server(port, conn_timeout, read_timout):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind(("127.0.0.1", port))
    server_socket.listen(1)  # Apenas um cliente por vez

    # Configura o timeout para aceitar novas conexões
    server_socket.settimeout(conn_timeout)

    #print(f"Servidor HTTP escutando na porta {port}")

    try:
        client_socket, client_address = server_socket.accept()
        #print(f"Conexão recebida de {client_address}")

        # Inicia uma thread para lidar com a conexão
        connection_handler = threading.Thread(target=handle_connection, args=(client_socket,))
        connection_handler.start()

        # Define um limite de tempo para aguardar a conclusão da thread
        connection_handler.join(default_read_timeout)

        # Envia a resposta HTTP 200 OK
        if data:
            response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            client_socket.send(response.encode("utf-8"))

        # Fecha o socket do cliente
        client_socket.close()

        # Se a thread ainda estiver ativa (timeout não atingido), interrompe-a
        if connection_handler.is_alive():
            #print("Timeout alcançado para o tratamento da conexão. Encerrando a thread.")
            time.sleep(2)
            #client_socket.shutdown(socket.SHUT_WR)
            client_socket.close()
            connection_handler._stop()


    except socket.timeout:
        #print(f"Timeout alcançado para aguardar novas conexões. Fechando o servidor.")
        sys.exit(1)

    # Fecha o socket do servidor
    server_socket.close()

def is_int(value):
    try:
        int(value)
        return True
    except ValueError:
        return False

if __name__ == "__main__":

    default_server_port = 8080  # Porta configurável
    default_conn_timeout = 30  # Timeout configurável em segundos
    default_read_timeout = 5  # Timeout para leitura de dados em segundos

    server_port = sys.argv[1]
    conn_timeout = sys.argv[2]
    read_timeout = sys.argv[3]
    #test if any are empty
    if server_port == "":
        server_port = default_server_port
    if conn_timeout == "":
        conn_timeout = default_conn_timeout
    if read_timeout == "":
       read_timeout = default_read_timeout

    # Verifica se todos os argumentos são inteiros
    if not all(is_int(arg) for arg in [server_port, conn_timeout, read_timeout]):
        print("Todos os argumentos devem ser números inteiros.")
        sys.exit(1)  # Encerra o programa com um código de saída indicando 

    try:
        server_port = int(server_port)
        conn_timeout   = int(conn_timeout)
        read_timeout = int(read_timeout)
    except ValueError:
        print("Erro ao converter argumentos para inteiros.")
        sys.exit(1)  

    start_server(server_port, conn_timeout, read_timeout)
    if data:
        #print("Recebido:")
        print(data)
        sys.exit(0)
    else:
        #print("Nada recebido")
        sys.exit(1)
